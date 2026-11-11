import XCTest
import SwiftData
@testable import NetworkMind

@MainActor
final class ModelTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext { container.mainContext }

    override func setUp() async throws {
        container = DataStore.makeInMemoryContainer()
    }

    override func tearDown() async throws {
        container = nil
    }

    func testPersonDefaultsAndDerivedProperties() throws {
        let person = Person(name: "Ayesha Khan", title: "CTO", company: "Acme", source: .newContact)
        context.insert(person)
        try context.save()

        XCTAssertEqual(person.priority, .normal)
        XCTAssertEqual(person.source, .newContact)
        XCTAssertEqual(person.source.label, "New contact")
        XCTAssertEqual(person.initials, "AK")
        XCTAssertEqual(person.subtitle, "CTO · Acme")
        XCTAssertFalse(person.hasLocation)

        person.priority = .vip
        XCTAssertEqual(person.priorityRaw, 3)
    }

    func testMeetingRelationshipsAndCascadeDelete() throws {
        let person = Person(name: "Bilal")
        let meeting = Meeting(startedAt: Date(), endedAt: Date().addingTimeInterval(600))
        let opportunity = Opportunity(title: "Pilot project", why: "Needs analytics", suggestedNextStep: "Send deck")
        let todo = TodoItem(task: "Send deck", owner: .me, dueHint: "Friday")
        let draft = FollowUpDraft(channel: .email, tone: .formal, subject: "Great meeting", body: "Hi Bilal")
        context.insert(person)
        context.insert(meeting)
        context.insert(opportunity)
        context.insert(todo)
        context.insert(draft)
        meeting.person = person
        meeting.opportunities = [opportunity]
        meeting.todos = [todo]
        meeting.followUpDrafts = [draft]
        draft.person = person
        try context.save()

        XCTAssertEqual(person.meetings?.count, 1)
        XCTAssertEqual(person.followUpDrafts?.count, 1)
        XCTAssertEqual(opportunity.meeting?.id, meeting.id)

        context.delete(meeting)
        try context.save()

        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Opportunity>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<TodoItem>()), 0)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<FollowUpDraft>()), 0)
        // The person survives; their meeting list is nullified.
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 1)
        XCTAssertEqual(person.meetings?.count ?? 0, 0)
    }

    func testDeletingPersonKeepsMeetingAsUnassigned() throws {
        let person = Person(name: "Sara")
        let meeting = Meeting(startedAt: Date(), endedAt: Date())
        context.insert(person)
        context.insert(meeting)
        meeting.person = person
        try context.save()

        context.delete(person)
        try context.save()

        let meetings = try context.fetch(FetchDescriptor<Meeting>())
        XCTAssertEqual(meetings.count, 1)
        XCTAssertNil(meetings.first?.person)
    }

    func testTranscriptSegmentsRoundTrip() throws {
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let words = [
            TranscriptWord(text: "Hello", start: start, duration: 0.4, confidence: 0.9),
            TranscriptWord(text: "there", start: start.addingTimeInterval(0.5), duration: 0.3, confidence: 0.8),
        ]
        let segment = TranscriptSegment(start: start, end: start.addingTimeInterval(0.8), text: "Hello there", words: words)
        let meeting = Meeting(startedAt: start, endedAt: start.addingTimeInterval(60), segments: [segment])
        context.insert(meeting)
        try context.save()

        let fetched = try XCTUnwrap(context.fetch(FetchDescriptor<Meeting>()).first)
        XCTAssertEqual(fetched.transcriptSegments, [segment])
        XCTAssertEqual(fetched.transcriptText, "Hello there")
        XCTAssertEqual(fetched.transcriptSegments.first?.words.last?.end, start.addingTimeInterval(0.8))
    }

    func testSegmentsOverlappingWindow() {
        let base = Date(timeIntervalSince1970: 0)
        let segments = (0..<5).map { i in
            TranscriptSegment(start: base.addingTimeInterval(Double(i) * 60),
                              end: base.addingTimeInterval(Double(i) * 60 + 50),
                              text: "s\(i)")
        }
        let window = segments.overlapping(start: base.addingTimeInterval(55), end: base.addingTimeInterval(130))
        XCTAssertEqual(window.map(\.text), ["s1", "s2"])
    }

    func testRecordingSessionChunksAndStatus() throws {
        let session = RecordingSession(startedAt: Date(), consentText: "I will inform people", consentAcknowledgedAt: Date())
        context.insert(session)
        let chunkB = RecordingChunk(index: 1, fileName: "b.m4a", startedAt: Date())
        let chunkA = RecordingChunk(index: 0, fileName: "a.m4a", startedAt: Date())
        context.insert(chunkB)
        context.insert(chunkA)
        session.chunks = [chunkB, chunkA]
        chunkB.audioDeleted = true
        try context.save()

        XCTAssertEqual(session.status, .recording)
        XCTAssertTrue(session.status.isLive)
        XCTAssertFalse(session.needsProcessing)
        XCTAssertEqual(session.sortedChunks.map(\.index), [0, 1])
        XCTAssertEqual(session.audioFileURLs.map(\.lastPathComponent), ["a.m4a"])

        session.status = .stopped
        XCTAssertTrue(session.needsProcessing)

        context.delete(session)
        try context.save()
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<RecordingChunk>()), 0)
    }

    func testUnknownRawValuesFallBackSafely() {
        let todo = TodoItem(task: "x")
        todo.ownerRaw = "garbage"
        XCTAssertEqual(todo.owner, .me)

        let draft = FollowUpDraft(channel: .iMessage, tone: .short, body: "hi")
        draft.statusRaw = "nope"
        XCTAssertEqual(draft.status, .draft)
        XCTAssertEqual(draft.channel, .iMessage)
    }

    func testTodoCompletionTimestamp() {
        let todo = TodoItem(task: "Call back")
        todo.setDone(true)
        XCTAssertNotNil(todo.completedAt)
        todo.setDone(false)
        XCTAssertNil(todo.completedAt)
    }

    func testSettingsDefaults() {
        let defaults = UserDefaults(suiteName: "test-\(UUID().uuidString)")!
        let settings = AppSettings(defaults: defaults)
        XCTAssertTrue(settings.deleteAudioAfterTranscription)
        XCTAssertFalse(settings.allowServerRecognition)
        XCTAssertEqual(settings.eventModeAutoStopHours, 10)
        XCTAssertEqual(settings.eventModeAutoStopInterval, 36_000)
        XCTAssertEqual(settings.tone, .friendly)

        settings.tone = .formal
        XCTAssertEqual(AppSettings(defaults: defaults).tone, .formal)
    }
}
