import Foundation
import AVFoundation
import SwiftData
import UIKit
import os

/// Owns Event Mode: the user turns it ON once (after a per-session consent confirmation)
/// and audio is recorded in short AAC chunks until they turn it OFF, it auto-stops, or a
/// safety guard (battery/storage) trips.
///
/// iOS shows the orange microphone indicator for the whole time; the app adds a persistent
/// banner and a Live Activity. Recording continues in the background via the `audio`
/// background mode. Nothing here starts the microphone without the user's explicit action.
@MainActor
final class EventModeManager: NSObject, ObservableObject {
    static let shared = EventModeManager()

    /// Chunk length: a crash or kill loses at most this much audio.
    static let chunkDuration: TimeInterval = 5 * 60
    static let guardInterval: TimeInterval = 15
    static let consentText = "I will inform people I'm recording for notes."
    static let didStopNotification = Notification.Name("EventModeManager.didStop")

    enum StartError: LocalizedError {
        case microphoneDenied
        case blocked(EventModeStopReason)
        case notConfigured
        case recorderFailed

        var errorDescription: String? {
            switch self {
            case .microphoneDenied: "Microphone access is off. Turn it on in Settings › NetworkMind to use Event Mode."
            case .blocked(.lowBattery): "Battery is below 10%. Plug in to start Event Mode."
            case .blocked(.lowStorage): "Not enough free storage to record. Free up at least 200 MB."
            case .blocked: "Event Mode can't start right now."
            case .notConfigured: "Event Mode isn't ready yet. Try again in a moment."
            case .recorderFailed: "The recorder couldn't start. Check that no other app is using the microphone."
            }
        }
    }

    @Published private(set) var activeSessionID: UUID?
    @Published private(set) var startedAt: Date?
    @Published private(set) var autoStopAt: Date?
    @Published private(set) var isInterrupted = false
    @Published private(set) var warning: String?
    @Published private(set) var lastStopMessage: String?
    /// Set by intents/controls: the UI presents the consent sheet when true.
    @Published var pendingStartRequest = false

    var isActive: Bool { activeSessionID != nil }

    private var container: ModelContainer?
    private var recorder: AVAudioRecorder?
    private var currentChunkID: UUID?
    private var currentChunkStartedAt: Date?
    private var guardTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: "com.networkmind.app", category: "EventMode")

    private static let recorderSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatMPEG4AAC,
        AVSampleRateKey: 16_000,
        AVNumberOfChannelsKey: 1,
        AVEncoderBitRateKey: 32_000,
        AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]

    // MARK: Setup

    func configure(container: ModelContainer) {
        guard self.container == nil else { return }
        self.container = container
        EventModeIntentBridge.stopHandler = { [weak self] in self?.stop(reason: .user) }
        EventModeIntentBridge.toggleHandler = { [weak self] in self?.toggleFromShortcut() }
        recoverOrphanedSessions()
    }

    private var context: ModelContext? { container?.mainContext }

    /// Intents/controls can't show consent UI, so starting opens the in-app confirmation.
    func toggleFromShortcut() {
        if isActive {
            stop(reason: .user)
        } else {
            pendingStartRequest = true
        }
    }

    static var microphonePermission: AVAudioApplication.recordPermission {
        AVAudioApplication.shared.recordPermission
    }

    // MARK: Start

    /// Starts Event Mode. Call only after the user confirmed `consentText` for this session.
    func start(consentAcknowledgedAt: Date = Date()) async throws {
        guard !isActive else { return }
        guard let context else { throw StartError.notConfigured }

        switch Self.microphonePermission {
        case .granted: break
        case .denied: throw StartError.microphoneDenied
        default:
            guard await AVAudioApplication.requestRecordPermission() else { throw StartError.microphoneDenied }
        }

        if let reason = EventModeGuards.canStart(conditions: Self.sampleDeviceConditions()) {
            throw StartError.blocked(reason)
        }

        try configureAudioSession()

        let now = Date()
        let autoStop = now.addingTimeInterval(AppSettings.shared.eventModeAutoStopInterval)
        let session = RecordingSession(startedAt: now, autoStopAt: autoStop, consentText: Self.consentText, consentAcknowledgedAt: consentAcknowledgedAt)
        context.insert(session)
        context.insert(ConsentRecord(kind: .eventSession, text: Self.consentText, sessionID: session.id, acknowledgedAt: consentAcknowledgedAt))
        try context.save()

        activeSessionID = session.id
        startedAt = now
        autoStopAt = autoStop
        isInterrupted = false
        warning = nil
        lastStopMessage = nil

        do {
            try startNewChunk()
        } catch {
            session.status = .failed
            session.lastError = error.localizedDescription
            session.endedAt = Date()
            try? context.save()
            resetState()
            deactivateAudioSession()
            throw StartError.recorderFailed
        }

        UIDevice.current.isBatteryMonitoringEnabled = true
        startObservers()
        startGuardTimer()
        EventModeLiveActivityController.start(startedAt: now, autoStopAt: autoStop)
        logger.info("Event Mode started, session \(session.id.uuidString)")
    }

    private func configureAudioSession() throws {
        let audio = AVAudioSession.sharedInstance()
        // playAndRecord + mixWithOthers: the user's own audio keeps playing and other apps
        // are less likely to interrupt us.
        try audio.setCategory(.playAndRecord, mode: .default, options: [.mixWithOthers, .allowBluetooth, .defaultToSpeaker])
        try audio.setActive(true)
    }

    private func deactivateAudioSession() {
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    // MARK: Chunks

    private func activeSession() -> RecordingSession? {
        guard let id = activeSessionID, let context else { return nil }
        let descriptor = FetchDescriptor<RecordingSession>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func currentChunk() -> RecordingChunk? {
        guard let id = currentChunkID, let context else { return nil }
        let descriptor = FetchDescriptor<RecordingChunk>(predicate: #Predicate { $0.id == id })
        return try? context.fetch(descriptor).first
    }

    private func startNewChunk() throws {
        guard let session = activeSession(), let context else { throw StartError.notConfigured }
        let index = (session.chunks ?? []).map(\.index).max().map { $0 + 1 } ?? 0
        let now = Date()
        let fileName = "\(session.id.uuidString)-\(String(format: "%03d", index)).m4a"
        let url = StoragePaths.recordingsDirectory.appendingPathComponent(fileName)

        let recorder = try AVAudioRecorder(url: url, settings: Self.recorderSettings)
        recorder.delegate = self
        guard recorder.prepareToRecord(), recorder.record() else { throw StartError.recorderFailed }
        try? FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: url.path)

        let chunk = RecordingChunk(index: index, fileName: fileName, startedAt: now)
        context.insert(chunk)
        chunk.session = session
        session.status = .recording
        try context.save()

        self.recorder = recorder
        currentChunkID = chunk.id
        currentChunkStartedAt = now
    }

    /// Stops the recorder and marks the chunk ready for transcription (or drops it if empty).
    private func finalizeCurrentChunk() {
        recorder?.stop()
        recorder = nil
        guard let chunk = currentChunk(), let context else { return }
        chunk.endedAt = Date()
        if Self.fileHasAudio(chunk.fileURL) {
            chunk.status = .pendingTranscription
        } else {
            try? FileManager.default.removeItem(at: chunk.fileURL)
            context.delete(chunk)
        }
        try? context.save()
        currentChunkID = nil
        currentChunkStartedAt = nil
    }

    private func rotateChunk() {
        finalizeCurrentChunk()
        do {
            try startNewChunk()
        } catch {
            logger.error("Chunk rotation failed: \(error.localizedDescription)")
            markInterrupted()
        }
    }

    nonisolated static func fileHasAudio(_ url: URL) -> Bool {
        let size = (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value ?? 0
        return size > 4096
    }

    // MARK: Stop

    func stop(reason: EventModeStopReason) {
        guard isActive else { return }
        finalizeCurrentChunk()
        if let session = activeSession() {
            session.endedAt = Date()
            session.stopReason = reason.rawValue
            session.status = (session.chunks ?? []).isEmpty ? .processed : .stopped
            try? context?.save()
        }
        stopObservers()
        guardTimer?.invalidate()
        guardTimer = nil
        deactivateAudioSession()
        EventModeLiveActivityController.endAll()
        UIDevice.current.isBatteryMonitoringEnabled = false
        let stoppedID = activeSessionID
        resetState()
        lastStopMessage = reason.message
        logger.info("Event Mode stopped: \(reason.rawValue)")
        NotificationCenter.default.post(name: Self.didStopNotification, object: stoppedID)
    }

    private func resetState() {
        activeSessionID = nil
        startedAt = nil
        autoStopAt = nil
        isInterrupted = false
        warning = nil
    }

    // MARK: Guards

    private func startGuardTimer() {
        guardTimer?.invalidate()
        let timer = Timer(timeInterval: Self.guardInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.guardTick() }
        }
        timer.tolerance = 2
        RunLoop.main.add(timer, forMode: .common)
        guardTimer = timer
    }

    private func guardTick() {
        guard isActive else { return }
        switch EventModeGuards.evaluate(conditions: Self.sampleDeviceConditions(), now: Date(), autoStopAt: autoStopAt) {
        case .stop(let reason):
            stop(reason: reason)
            return
        case .warn(let message):
            warning = message
        case .ok:
            warning = nil
        }
        if isInterrupted {
            attemptResume()
        } else if let started = currentChunkStartedAt,
                  EventModeGuards.shouldRotateChunk(startedAt: started, now: Date(), chunkDuration: Self.chunkDuration) {
            rotateChunk()
        } else if recorder?.isRecording == false {
            // The system stopped the recorder without telling us (e.g. after a reset).
            rotateChunk()
        }
    }

    static func sampleDeviceConditions() -> DeviceConditions {
        let device = UIDevice.current
        let free = try? URL(fileURLWithPath: NSHomeDirectory())
            .resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            .volumeAvailableCapacityForImportantUsage
        return DeviceConditions(
            batteryLevel: device.isBatteryMonitoringEnabled ? device.batteryLevel : -1,
            isCharging: device.batteryState == .charging || device.batteryState == .full,
            freeBytes: free
        )
    }

    // MARK: Interruptions

    private func startObservers() {
        let center = NotificationCenter.default
        let audio = AVAudioSession.sharedInstance()
        observers = [
            center.addObserver(forName: AVAudioSession.interruptionNotification, object: audio, queue: .main) { [weak self] note in
                let typeValue = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt
                Task { @MainActor in self?.handleInterruption(typeValue: typeValue) }
            },
            center.addObserver(forName: AVAudioSession.routeChangeNotification, object: audio, queue: .main) { [weak self] note in
                let reasonValue = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
                Task { @MainActor in self?.handleRouteChange(reasonValue: reasonValue) }
            },
            center.addObserver(forName: AVAudioSession.mediaServicesWereResetNotification, object: audio, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.handleMediaServicesReset() }
            },
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isInterrupted else { return }
                    self.attemptResume()
                }
            },
        ]
    }

    private func stopObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }

    private func handleInterruption(typeValue: UInt?) {
        guard isActive, let typeValue, let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            logger.info("Audio interruption began")
            markInterrupted()
        case .ended:
            logger.info("Audio interruption ended")
            attemptResume()
        @unknown default:
            break
        }
    }

    private func markInterrupted() {
        finalizeCurrentChunk()
        isInterrupted = true
        if let session = activeSession() {
            session.status = .interrupted
            try? context?.save()
        }
        if let autoStopAt { EventModeLiveActivityController.update(isInterrupted: true, autoStopAt: autoStopAt) }
    }

    /// Reactivates the session and starts a fresh chunk. Retried on every guard tick and
    /// when the app becomes active, because iOS may refuse while a call is still ending.
    private func attemptResume() {
        guard isActive, isInterrupted else { return }
        do {
            try configureAudioSession()
            try startNewChunk()
            isInterrupted = false
            if let autoStopAt { EventModeLiveActivityController.update(isInterrupted: false, autoStopAt: autoStopAt) }
            logger.info("Recording resumed after interruption")
        } catch {
            logger.debug("Resume not possible yet: \(error.localizedDescription)")
        }
    }

    private func handleRouteChange(reasonValue: UInt?) {
        guard isActive, !isInterrupted, let reasonValue,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue) else { return }
        switch reason {
        case .oldDeviceUnavailable, .newDeviceAvailable:
            // A new input (headset/AirPods/car) can change the format; start a clean file.
            rotateChunk()
        default:
            break
        }
    }

    private func handleMediaServicesReset() {
        guard isActive else { return }
        logger.error("Media services were reset; rebuilding recorder")
        recorder = nil
        markInterrupted()
        attemptResume()
    }

    // MARK: Crash recovery

    /// Sessions still marked live at launch were cut short (crash, kill, reboot): close
    /// them and keep whatever audio is readable.
    private func recoverOrphanedSessions() {
        guard let context, !isActive else { return }
        let live = [RecordingStatus.recording.rawValue, RecordingStatus.interrupted.rawValue]
        let descriptor = FetchDescriptor<RecordingSession>(predicate: #Predicate { live.contains($0.statusRaw) })
        guard let orphans = try? context.fetch(descriptor), !orphans.isEmpty else { return }
        for session in orphans {
            for chunk in session.chunks ?? [] where chunk.status == .recording {
                if Self.isReadableAudio(chunk.fileURL) {
                    chunk.status = .pendingTranscription
                    chunk.endedAt = chunk.endedAt ?? Self.modificationDate(of: chunk.fileURL) ?? chunk.startedAt
                } else {
                    // An AAC/M4A file that was never finalized can't be decoded.
                    try? FileManager.default.removeItem(at: chunk.fileURL)
                    context.delete(chunk)
                }
            }
            let lastEnd = session.sortedChunks.compactMap(\.endedAt).max()
            session.endedAt = lastEnd ?? session.startedAt
            session.stopReason = EventModeStopReason.crashRecovery.rawValue
            session.status = (session.chunks ?? []).isEmpty ? .processed : .stopped
        }
        try? context.save()
        EventModeLiveActivityController.endAll()
        lastStopMessage = EventModeStopReason.crashRecovery.message
    }

    nonisolated static func isReadableAudio(_ url: URL) -> Bool {
        guard fileHasAudio(url), let file = try? AVAudioFile(forReading: url) else { return false }
        return file.length > 0
    }

    nonisolated private static func modificationDate(of url: URL) -> Date? {
        try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date
    }
}

extension EventModeManager: AVAudioRecorderDelegate {
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        Task { @MainActor in
            self.logger.error("Encoder error: \(error?.localizedDescription ?? "unknown")")
            self.markInterrupted()
            self.attemptResume()
        }
    }
}
