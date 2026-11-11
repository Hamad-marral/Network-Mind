import Foundation
import SwiftData

/// One Event Mode run: from the moment the user turns Event Mode ON until it is turned
/// OFF (or auto-stops). Audio is captured as a series of short `RecordingChunk` files so a
/// crash loses at most one chunk.
@Model
final class RecordingSession {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date?
    /// When Event Mode will stop by itself (default: start + 10 hours).
    var autoStopAt: Date?
    var statusRaw: String = RecordingStatus.recording.rawValue
    var lastError: String?
    /// Reason Event Mode stopped ("user", "autoStop", "lowBattery", "lowStorage", "crashRecovery").
    var stopReason: String?

    /// When the user confirmed "I will inform people I'm recording for notes." for this session.
    var consentAcknowledgedAt: Date?
    var consentText: String = ""

    /// Merged, JSON-encoded `[TranscriptSegment]` for the whole session.
    @Attribute(.externalStorage) var transcriptData: Data?
    var transcriptionProgress: Double = 0

    @Relationship(deleteRule: .cascade, inverse: \RecordingChunk.session)
    var chunks: [RecordingChunk]? = []

    @Relationship(deleteRule: .nullify, inverse: \Meeting.session)
    var meetings: [Meeting]? = []

    init(startedAt: Date = Date(), autoStopAt: Date? = nil, consentText: String = "", consentAcknowledgedAt: Date? = nil) {
        self.id = UUID()
        self.startedAt = startedAt
        self.autoStopAt = autoStopAt
        self.consentText = consentText
        self.consentAcknowledgedAt = consentAcknowledgedAt
        self.statusRaw = RecordingStatus.recording.rawValue
    }

    var status: RecordingStatus {
        get { RecordingStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var transcriptSegments: [TranscriptSegment] {
        get { ModelCoding.decode([TranscriptSegment].self, from: transcriptData) ?? [] }
        set { transcriptData = ModelCoding.encode(newValue) }
    }

    var sortedChunks: [RecordingChunk] { (chunks ?? []).sorted { $0.index < $1.index } }

    var sortedMeetings: [Meeting] { (meetings ?? []).sorted { $0.startedAt < $1.startedAt } }

    /// Absolute URLs of the audio files that still exist on disk.
    var audioFileURLs: [URL] {
        sortedChunks.compactMap { $0.audioDeleted ? nil : $0.fileURL }
    }

    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt) }

    /// True if any step still needs to run (or be retried).
    var needsProcessing: Bool {
        switch status {
        case .recording, .interrupted, .processed: false
        default: true
        }
    }
}

/// A short audio file (e.g. 5 minutes, AAC) belonging to a session.
@Model
final class RecordingChunk {
    var id: UUID = UUID()
    var index: Int = 0
    /// File name relative to the recordings directory. Absolute container paths change
    /// between installs/updates, so only the name is persisted.
    var fileName: String = ""
    var startedAt: Date = Date()
    var endedAt: Date?
    var statusRaw: String = ChunkStatus.recording.rawValue
    var audioDeleted: Bool = false
    var transcriptionAttempts: Int = 0
    var errorMessage: String?
    /// JSON-encoded `[TranscriptSegment]` for this chunk only.
    @Attribute(.externalStorage) var transcriptData: Data?

    var session: RecordingSession?

    init(index: Int, fileName: String, startedAt: Date) {
        self.id = UUID()
        self.index = index
        self.fileName = fileName
        self.startedAt = startedAt
        self.statusRaw = ChunkStatus.recording.rawValue
    }

    var status: ChunkStatus {
        get { ChunkStatus(rawValue: statusRaw) ?? .failed }
        set { statusRaw = newValue.rawValue }
    }

    var fileURL: URL { StoragePaths.recordingsDirectory.appendingPathComponent(fileName) }

    var transcriptSegments: [TranscriptSegment] {
        get { ModelCoding.decode([TranscriptSegment].self, from: transcriptData) ?? [] }
        set { transcriptData = ModelCoding.encode(newValue) }
    }
}
