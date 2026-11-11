import Foundation
import SwiftData

/// One conversation with one person, cut out of a `RecordingSession` by segmentation
/// and enriched by AI analysis.
@Model
final class Meeting {
    var id: UUID = UUID()
    var startedAt: Date = Date()
    var endedAt: Date = Date()

    var person: Person?
    var session: RecordingSession?

    /// JSON-encoded `[TranscriptSegment]`. Use `transcriptSegments`.
    @Attribute(.externalStorage) var transcriptData: Data?

    var summary: String = ""
    var topics: [String] = []
    var needsOfThem: [String] = []
    var offersFromThem: [String] = []
    var promisedFollowups: [String] = []
    var keyFacts: [String] = []
    var suggestedCollaborations: [String] = []
    var sentimentRaw: String?
    /// Language of the conversation detected by analysis ("en", "ur", "ur-Latn").
    var language: String?

    /// Segmentation metadata.
    var segmentConfidence: Double = 0
    var segmentReason: String = ""
    var analysisStatusRaw: String = AnalysisStatus.pending.rawValue
    var analysisError: String?
    var createdAt: Date = Date()

    @Relationship(deleteRule: .cascade, inverse: \Opportunity.meeting)
    var opportunities: [Opportunity]? = []

    @Relationship(deleteRule: .cascade, inverse: \TodoItem.meeting)
    var todos: [TodoItem]? = []

    @Relationship(deleteRule: .cascade, inverse: \FollowUpDraft.meeting)
    var followUpDrafts: [FollowUpDraft]? = []

    /// Relationships (`person`, `session`) are assigned by callers *after* inserting the
    /// meeting into a context; linking un-inserted models is a common SwiftData crash source.
    init(startedAt: Date, endedAt: Date, segments: [TranscriptSegment] = []) {
        self.id = UUID()
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.transcriptData = ModelCoding.encode(segments)
        self.createdAt = Date()
    }

    var transcriptSegments: [TranscriptSegment] {
        get { ModelCoding.decode([TranscriptSegment].self, from: transcriptData) ?? [] }
        set { transcriptData = ModelCoding.encode(newValue) }
    }

    var transcriptText: String { transcriptSegments.plainText }

    var sentiment: Sentiment? {
        get { sentimentRaw.flatMap(Sentiment.init(rawValue:)) }
        set { sentimentRaw = newValue?.rawValue }
    }

    var analysisStatus: AnalysisStatus {
        get { AnalysisStatus(rawValue: analysisStatusRaw) ?? .pending }
        set { analysisStatusRaw = newValue.rawValue }
    }

    var duration: TimeInterval { max(0, endedAt.timeIntervalSince(startedAt)) }

    var sortedTodos: [TodoItem] { (todos ?? []).sorted { $0.createdAt < $1.createdAt } }
    var sortedOpportunities: [Opportunity] { (opportunities ?? []).sorted { $0.createdAt < $1.createdAt } }
    var sortedDrafts: [FollowUpDraft] { (followUpDrafts ?? []).sorted { $0.updatedAt > $1.updatedAt } }
}
