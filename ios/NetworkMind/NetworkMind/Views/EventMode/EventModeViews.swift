import SwiftUI
import AVFoundation

/// Per-session confirmation shown before every Event Mode start.
struct EventModeConsentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var manager = EventModeManager.shared
    @State private var confirmed = false
    @State private var isStarting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                Label("Start Event Mode", systemImage: "mic.circle.fill")
                    .font(.title2.bold())
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 10) {
                    InfoLine(systemImage: "waveform", text: "Your phone records conversations so you get notes, summaries and follow-ups tonight.")
                    InfoLine(systemImage: "clock", text: "Stops automatically after \(Int(settings.eventModeAutoStopHours)) hours, or whenever you turn it off.")
                    InfoLine(systemImage: "battery.25", text: "Stops by itself if the battery drops below 10%.")
                    InfoLine(systemImage: "lock.fill", text: settings.deleteAudioAfterTranscription
                        ? "Audio stays on this phone and is deleted after transcription."
                        : "Audio stays on this phone until you delete it.")
                }

                Toggle(isOn: $confirmed) {
                    Text(EventModeManager.consentText).font(.headline)
                }
                .toggleStyle(CheckboxToggleStyle())
                .padding()
                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                .accessibilityIdentifier("eventConsentToggle")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }

                Spacer()

                Button {
                    Task { await start() }
                } label: {
                    Group {
                        if isStarting { ProgressView() } else { Text("Start recording") }
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .controlSize(.large)
                .disabled(!confirmed || isStarting)
                .accessibilityIdentifier("startEventModeButton")
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.large])
    }

    private func start() async {
        isStarting = true
        defer { isStarting = false }
        do {
            try await manager.start(consentAcknowledgedAt: Date())
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct InfoLine: View {
    let systemImage: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: systemImage)
                .frame(width: 22)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(text).font(.subheadline)
        }
    }
}

/// Persistent in-app banner while Event Mode is on (in addition to the system mic indicator).
struct EventModeBanner: View {
    @ObservedObject private var manager = EventModeManager.shared

    var body: some View {
        if manager.isActive, let startedAt = manager.startedAt {
            VStack(spacing: 4) {
                HStack(spacing: 10) {
                    Circle()
                        .fill(manager.isInterrupted ? Color.orange : Color.red)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(manager.isInterrupted ? "Event Mode paused" : "Event Mode: recording")
                            .font(.subheadline.bold())
                        Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Stop") { manager.stop(reason: .user) }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                        .controlSize(.small)
                        .accessibilityIdentifier("bannerStopButton")
                }
                if let warning = manager.warning {
                    Text(warning)
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.regularMaterial)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(manager.isInterrupted ? "Event Mode paused" : "Event Mode is recording")
        }
    }
}

/// Today-tab card with the main Event Mode switch.
struct EventModeCard: View {
    @ObservedObject private var manager = EventModeManager.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("Event Mode", systemImage: manager.isActive ? "mic.fill" : "mic")
                    .font(.headline)
                    .foregroundStyle(manager.isActive ? Color.red : Color.primary)
                Spacer()
                if manager.isActive, let startedAt = manager.startedAt {
                    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            Text(manager.isActive
                 ? "Recording conversations for tonight's digest. Remember to tell people you're taking notes."
                 : "Turn on before a conference or a day of meetings. No tapping needed during conversations.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            if let message = manager.lastStopMessage, !manager.isActive {
                Text(message).font(.footnote).foregroundStyle(.secondary)
            }
            Button {
                if manager.isActive {
                    manager.stop(reason: .user)
                } else {
                    manager.pendingStartRequest = true
                }
            } label: {
                Text(manager.isActive ? "Turn off Event Mode" : "Turn on Event Mode")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(manager.isActive ? Color.red : Color.accentColor)
            .accessibilityIdentifier("eventModeToggleButton")
        }
        .padding(.vertical, 4)
    }
}
