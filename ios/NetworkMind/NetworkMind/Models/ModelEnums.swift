import Foundation

// Enums are persisted as raw values on the SwiftData models (see `...Raw` properties).
// Storing raw primitives keeps the schema CloudKit-compatible and avoids SwiftData's
// fragile handling of enum-typed attributes inside predicates.

/// How a person entered the app. Note: there is no public NameDrop API, so contacts that
/// appear in Apple Contacts are always labelled "New contact" — never "from NameDrop".
enum PersonSource: String, Codable, CaseIterable, Sendable {
    case newContact
    case manual
    case businessCard
    case demo

    var label: String {
        switch self {
        case .newContact: "New contact"
        case .manual: "Added manually"
        case .businessCard: "Business card"
        case .demo: "Demo data"
        }
    }
}

enum Priority: Int, Codable, CaseIterable, Comparable, Identifiable, Sendable {
    case low = 0
    case normal = 1
    case high = 2
    case vip = 3

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .low: "Low"
        case .normal: "Normal"
        case .high: "High"
        case .vip: "VIP"
        }
    }

    static func < (lhs: Priority, rhs: Priority) -> Bool { lhs.rawValue < rhs.rawValue }
}

enum RecordingStatus: String, Codable, CaseIterable, Sendable {
    /// Event Mode is on and audio is being captured.
    case recording
    /// Capture paused by the system (phone call, Siri, route loss); will resume.
    case interrupted
    /// Event Mode is off; chunks wait for transcription.
    case stopped
    case transcribing
    case transcribed
    case segmenting
    case segmented
    case analyzing
    /// Every step of the pipeline finished.
    case processed
    case failed

    var label: String {
        switch self {
        case .recording: "Recording"
        case .interrupted: "Interrupted"
        case .stopped: "Waiting to process"
        case .transcribing: "Transcribing"
        case .transcribed: "Transcribed"
        case .segmenting: "Finding conversations"
        case .segmented: "Conversations found"
        case .analyzing: "Analyzing"
        case .processed: "Processed"
        case .failed: "Needs attention"
        }
    }

    /// True while Event Mode owns the session.
    var isLive: Bool { self == .recording || self == .interrupted }
}

enum ChunkStatus: String, Codable, CaseIterable, Sendable {
    case recording
    case pendingTranscription
    case transcribing
    case transcribed
    case failed
}

enum Sentiment: String, Codable, CaseIterable, Sendable {
    case positive
    case neutral
    case negative
    case mixed

    var label: String { rawValue.capitalized }

    var symbolName: String {
        switch self {
        case .positive: "face.smiling"
        case .neutral: "minus.circle"
        case .negative: "hand.thumbsdown"
        case .mixed: "arrow.left.arrow.right"
        }
    }
}

enum TodoOwner: String, Codable, CaseIterable, Sendable {
    case me
    case them

    var label: String { self == .me ? "Me" : "Them" }
}

enum FollowUpChannel: String, Codable, CaseIterable, Identifiable, Sendable {
    case whatsapp
    case email
    case iMessage

    var id: String { rawValue }

    var label: String {
        switch self {
        case .whatsapp: "WhatsApp"
        case .email: "Email"
        case .iMessage: "iMessage"
        }
    }

    var symbolName: String {
        switch self {
        case .whatsapp: "bubble.left.and.bubble.right"
        case .email: "envelope"
        case .iMessage: "message"
        }
    }
}

enum DraftStatus: String, Codable, CaseIterable, Sendable {
    case draft
    case sent
    case dismissed
}

enum FollowUpTone: String, Codable, CaseIterable, Identifiable, Sendable {
    case formal
    case friendly
    case short

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

enum AnalysisStatus: String, Codable, CaseIterable, Sendable {
    case pending
    case analyzing
    case analyzed
    case failed
}

enum ConsentKind: String, Codable, CaseIterable, Sendable {
    /// First-launch legal/recording-law acknowledgment.
    case legalTerms
    /// Per-Event-Mode-session "I will inform people I'm recording for notes."
    case eventSession
}
