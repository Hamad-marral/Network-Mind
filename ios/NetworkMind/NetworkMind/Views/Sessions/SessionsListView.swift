import SwiftUI
import SwiftData

struct SessionsListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RecordingSession.startedAt, order: .reverse) private var sessions: [RecordingSession]

    var body: some View {
        NavigationStack {
            Group {
                if sessions.isEmpty {
                    ContentUnavailableView(
                        "No sessions",
                        systemImage: "waveform",
                        description: Text("Turn on Event Mode before a conference or meeting day. Each run appears here.")
                    )
                } else {
                    List {
                        ForEach(sessions) { session in
                            NavigationLink(value: session) { SessionRow(session: session) }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationDestination(for: RecordingSession.self) { SessionDetailView(session: $0) }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets {
            let session = sessions[index]
            guard !session.status.isLive else { continue }
            for url in session.audioFileURLs { try? FileManager.default.removeItem(at: url) }
            modelContext.delete(session)
        }
        try? modelContext.save()
    }
}

struct SessionRow: View {
    let session: RecordingSession

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.startedAt, format: .dateTime.weekday(.wide).month().day().hour().minute())
                .font(.headline)
            HStack(spacing: 8) {
                TagChip(text: session.status.label, color: session.status.color)
                Text(session.duration.compactDuration)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                let count = session.meetings?.count ?? 0
                if count > 0 {
                    Text("\(count) conversation\(count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }
}

struct SessionDetailView: View {
    let session: RecordingSession

    var body: some View {
        List {
            Section("Session") {
                LabeledContent("Started", value: session.startedAt.formatted(date: .abbreviated, time: .shortened))
                if let ended = session.endedAt {
                    LabeledContent("Ended", value: ended.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Duration", value: session.duration.compactDuration)
                LabeledContent("Status", value: session.status.label)
                if let consent = session.consentAcknowledgedAt {
                    LabeledContent("Consent confirmed", value: consent.formatted(date: .omitted, time: .shortened))
                }
                if let error = session.lastError {
                    Text(error).foregroundStyle(.red).font(.footnote)
                }
            }
            Section("Audio chunks (\(session.sortedChunks.count))") {
                ForEach(session.sortedChunks) { chunk in
                    HStack {
                        Text("Chunk \(chunk.index + 1)")
                        Spacer()
                        Text(chunk.status.rawValue).font(.caption).foregroundStyle(.secondary)
                        if chunk.audioDeleted {
                            Image(systemName: "trash").foregroundStyle(.secondary)
                                .accessibilityLabel("Audio deleted")
                        }
                    }
                }
            }
            if !session.sortedMeetings.isEmpty {
                Section("Conversations") {
                    ForEach(session.sortedMeetings) { meeting in
                        VStack(alignment: .leading) {
                            Text(meeting.person?.displayName ?? "Unknown person").font(.headline)
                            Text("\(meeting.startedAt.formatted(date: .omitted, time: .shortened)) – \(meeting.endedAt.formatted(date: .omitted, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle("Session")
        .navigationBarTitleDisplayMode(.inline)
    }
}
