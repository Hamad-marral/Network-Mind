import XCTest
import SwiftData
@testable import NetworkMind

// MARK: - Fakes

private final class FakeHistorySource: ContactHistorySource {
    struct Failure: Error {}

    var token = Data([1])
    var events: [ContactChangeEvent] = []
    var allIdentifiers: Set<String> = []
    var throwOnChanges = false
    private(set) var changesCalls = 0

    func currentHistoryToken() -> Data? { token }

    func changes(since token: Data) throws -> (events: [ContactChangeEvent], token: Data?) {
        changesCalls += 1
        if throwOnChanges { throw Failure() }
        return (events, self.token)
    }

    func allContactIdentifiers() throws -> Set<String> { allIdentifiers }
}

private final class MemoryStateStore: ContactSyncStateStore {
    var historyToken: Data?
    var knownIdentifiers: Set<String>?
}

// MARK: - Change history parsing

final class ContactChangeHistoryParserTests: XCTestCase {
    func testAddsAreReturnedInOrderWithoutDuplicates() {
        let summary = ContactChangeHistoryParser.summarize([.added("b"), .added("a"), .updated("a"), .added("b")])
        XCTAssertEqual(summary.addedIdentifiers, ["b", "a"])
        XCTAssertFalse(summary.requiresFullResync)
    }

    func testAddThenDeleteCancelsOut() {
        let summary = ContactChangeHistoryParser.summarize([.added("a"), .deleted("a")])
        XCTAssertEqual(summary.addedIdentifiers, [])
        XCTAssertEqual(summary.deletedIdentifiers, [])
    }

    func testDeleteThenReAddCountsAsAdd() {
        let summary = ContactChangeHistoryParser.summarize([.deleted("a"), .added("a")])
        XCTAssertEqual(summary.addedIdentifiers, ["a"])
        XCTAssertEqual(summary.deletedIdentifiers, [])
    }

    func testDeletionOfPreexistingContact() {
        let summary = ContactChangeHistoryParser.summarize([.deleted("x")])
        XCTAssertEqual(summary.deletedIdentifiers, ["x"])
    }

    func testDropEverythingRequiresResync() {
        let summary = ContactChangeHistoryParser.summarize([.dropEverything, .added("a"), .added("b")])
        XCTAssertTrue(summary.requiresFullResync)
    }

    func testDiffReturnsOnlyNewIdentifiersSorted() {
        let new = ContactChangeHistoryParser.diff(previous: ["a", "b", "c"], current: ["a", "d", "b", "e"])
        XCTAssertEqual(new, ["d", "e"])
    }
}

// MARK: - Engine

final class ContactChangeEngineTests: XCTestCase {
    private var source: FakeHistorySource!
    private var state: MemoryStateStore!
    private var engine: ContactChangeEngine { ContactChangeEngine(source: source, state: state) }

    override func setUp() {
        source = FakeHistorySource()
        state = MemoryStateStore()
    }

    func testFirstRunEstablishesBaselineWithoutImporting() throws {
        source.allIdentifiers = ["a", "b"]
        let outcome = try engine.detectNewContacts()
        XCTAssertEqual(outcome, .baselineEstablished(count: 2))
        XCTAssertEqual(outcome.newIdentifiers, [])
        XCTAssertEqual(state.knownIdentifiers, ["a", "b"])
        XCTAssertEqual(state.historyToken, Data([1]))
        XCTAssertEqual(source.changesCalls, 0)
    }

    func testIncrementalAddsAreNew() throws {
        state.historyToken = Data([1])
        state.knownIdentifiers = ["a", "b"]
        source.token = Data([2])
        source.events = [.added("c"), .updated("a")]

        let outcome = try engine.detectNewContacts()
        XCTAssertEqual(outcome, .incremental(newIdentifiers: ["c"]))
        XCTAssertEqual(state.knownIdentifiers, ["a", "b", "c"])
        XCTAssertEqual(state.historyToken, Data([2]))
    }

    func testAddOfAlreadyKnownContactIsNotNew() throws {
        state.historyToken = Data([1])
        state.knownIdentifiers = ["a"]
        source.events = [.added("a")]
        XCTAssertEqual(try engine.detectNewContacts().newIdentifiers, [])
    }

    func testDeletionsShrinkSnapshot() throws {
        state.historyToken = Data([1])
        state.knownIdentifiers = ["a", "b"]
        source.events = [.deleted("b")]
        _ = try engine.detectNewContacts()
        XCTAssertEqual(state.knownIdentifiers, ["a"])
    }

    func testDropEverythingFallsBackToDiff() throws {
        state.historyToken = Data([1])
        state.knownIdentifiers = ["a", "b", "c"]
        source.events = [.dropEverything, .added("a"), .added("b"), .added("d")]
        source.allIdentifiers = ["a", "b", "d"]
        source.token = Data([9])

        let outcome = try engine.detectNewContacts()
        XCTAssertEqual(outcome, .diffFallback(newIdentifiers: ["d"]))
        XCTAssertEqual(state.knownIdentifiers, ["a", "b", "d"])
        XCTAssertEqual(state.historyToken, Data([9]))
    }

    func testInvalidTokenFallsBackToDiff() throws {
        state.historyToken = Data([1])
        state.knownIdentifiers = ["a"]
        source.throwOnChanges = true
        source.allIdentifiers = ["a", "z"]

        let outcome = try engine.detectNewContacts()
        XCTAssertEqual(outcome, .diffFallback(newIdentifiers: ["z"]))
        XCTAssertEqual(state.knownIdentifiers, ["a", "z"])
    }

    func testDefaultsStateStoreRoundTrip() throws {
        let suite = "contacts-test-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(suite).json")
        let store = DefaultsContactSyncStateStore(defaults: defaults, snapshotURL: url)

        XCTAssertNil(store.historyToken)
        XCTAssertNil(store.knownIdentifiers)
        store.historyToken = Data([7, 7])
        store.knownIdentifiers = ["x", "y"]

        let reopened = DefaultsContactSyncStateStore(defaults: defaults, snapshotURL: url)
        XCTAssertEqual(reopened.historyToken, Data([7, 7]))
        XCTAssertEqual(reopened.knownIdentifiers, ["x", "y"])

        reopened.reset()
        XCTAssertNil(store.historyToken)
        XCTAssertNil(store.knownIdentifiers)
    }
}

// MARK: - Person import

@MainActor
final class PersonImporterTests: XCTestCase {
    func testImportDedupesByContactIdentifierAndAppliesContext() throws {
        let container = DataStore.makeInMemoryContainer()
        let context = container.mainContext
        context.insert(Person(name: "Existing", contactIdentifier: "c1", source: .manual))
        try context.save()

        let date = Date(timeIntervalSince1970: 1_750_000_000)
        let meetingContext = MeetingContext(date: date, latitude: 31.5, longitude: 74.3, placeName: "Expo Centre, Lahore", calendarEventTitle: "Fintech Summit")
        let snapshots = [
            ContactSnapshot(identifier: "c1", name: "Existing", jobTitle: "", organization: "", phones: [], emails: []),
            ContactSnapshot(identifier: "c2", name: "Ayesha Khan", jobTitle: "CTO", organization: "Nimbus", phones: ["+92 300 1234567"], emails: ["ayesha@nimbus.pk"]),
            ContactSnapshot(identifier: "c2", name: "Ayesha Khan (dup)", jobTitle: "", organization: "", phones: [], emails: []),
        ]

        let created = try PersonImporter.importContacts(snapshots, context: meetingContext, into: context)

        XCTAssertEqual(created.count, 1)
        let person = try XCTUnwrap(created.first)
        XCTAssertEqual(person.name, "Ayesha Khan")
        XCTAssertEqual(person.source, .newContact)
        XCTAssertEqual(person.firstMetAt, date)
        XCTAssertEqual(person.metPlaceName, "Expo Centre, Lahore")
        XCTAssertEqual(person.matchedCalendarEventTitle, "Fintech Summit")
        XCTAssertEqual(person.metLatitude, 31.5)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<Person>()), 2)
    }
}

// MARK: - Calendar matching

final class CalendarEventMatcherTests: XCTestCase {
    private let day = Date(timeIntervalSince1970: 1_750_000_000)
    private func at(_ hours: Double) -> Date { day.addingTimeInterval(hours * 3600) }

    func testPrefersShortestContainingEvent() {
        let events = [
            CalendarEventInfo(title: "Conference", start: at(9), end: at(17), isAllDay: false),
            CalendarEventInfo(title: "Panel talk", start: at(10), end: at(11), isAllDay: false),
            CalendarEventInfo(title: "Holiday", start: at(0), end: at(24), isAllDay: true),
        ]
        XCTAssertEqual(CalendarEventMatcher.bestMatch(for: at(10.5), in: events)?.title, "Panel talk")
        XCTAssertEqual(CalendarEventMatcher.bestMatch(for: at(12), in: events)?.title, "Conference")
    }

    func testToleranceAndContainmentPriority() {
        let events = [
            CalendarEventInfo(title: "Conference", start: at(9), end: at(17), isAllDay: false),
            CalendarEventInfo(title: "Breakfast", start: at(8), end: at(8.95), isAllDay: false),
        ]
        // 08:55 is inside Breakfast and within 10 min tolerance of Conference: containment wins.
        XCTAssertEqual(CalendarEventMatcher.bestMatch(for: at(8.9), in: events)?.title, "Breakfast")
        // 08:58 is after Breakfast (but within its tolerance) and before Conference: shortest wins.
        XCTAssertEqual(CalendarEventMatcher.bestMatch(for: at(8.97), in: events)?.title, "Breakfast")
    }

    func testNoMatchOutsideEventsOrForAllDay() {
        let events = [CalendarEventInfo(title: "Holiday", start: at(0), end: at(24), isAllDay: true)]
        XCTAssertNil(CalendarEventMatcher.bestMatch(for: at(12), in: events))
        XCTAssertNil(CalendarEventMatcher.bestMatch(for: at(12), in: []))
    }
}

// MARK: - Business cards

final class BusinessCardParserTests: XCTestCase {
    func testFullCard() {
        let card = BusinessCardParser.parse(lines: [
            "Ayesha Khan",
            "Chief Technology Officer",
            "Nimbus Technologies Pvt Ltd",
            "+92 300 1234567",
            "ayesha@nimbus.pk",
            "www.nimbus.pk",
            "Office 12, Block B, Gulberg III, Lahore",
        ])
        XCTAssertEqual(card.name, "Ayesha Khan")
        XCTAssertEqual(card.title, "Chief Technology Officer")
        XCTAssertEqual(card.company, "Nimbus Technologies Pvt Ltd")
        XCTAssertEqual(card.emails, ["ayesha@nimbus.pk"])
        XCTAssertEqual(card.phones.count, 1)
        XCTAssertEqual(card.websites, ["www.nimbus.pk"])
    }

    func testCompanyFromEmailDomainWhenNoCompanyLine() {
        let card = BusinessCardParser.parse(lines: ["Sara Ahmed", "Product Manager", "Sara.Ahmed@finlytics.io"])
        XCTAssertEqual(card.name, "Sara Ahmed")
        XCTAssertEqual(card.title, "Product Manager")
        XCTAssertEqual(card.company, "Finlytics")
        XCTAssertEqual(card.emails, ["sara.ahmed@finlytics.io"])
    }

    func testGenericEmailDomainIsNotACompany() {
        let card = BusinessCardParser.parse(lines: ["Bilal Raza", "Founder", "bilal.raza@gmail.com"])
        XCTAssertEqual(card.name, "Bilal Raza")
        XCTAssertEqual(card.title, "Founder")
        XCTAssertEqual(card.company, "")
    }

    func testLegalSuffixBeatsTitleKeyword() {
        let card = BusinessCardParser.parse(lines: ["Product Labs Inc", "Omar Farooq", "Sales Director"])
        XCTAssertEqual(card.company, "Product Labs Inc")
        XCTAssertEqual(card.name, "Omar Farooq")
        XCTAssertEqual(card.title, "Sales Director")
    }

    func testMultilineInputIsSplit() {
        let card = BusinessCardParser.parse(lines: ["Zara Malik\nDesign Lead"])
        XCTAssertEqual(card.name, "Zara Malik")
        XCTAssertEqual(card.title, "Design Lead")
    }

    func testNameSplitter() {
        XCTAssertEqual(PersonNameSplitter.split("Ayesha Khan").given, "Ayesha")
        XCTAssertEqual(PersonNameSplitter.split("Ayesha Khan").family, "Khan")
        XCTAssertEqual(PersonNameSplitter.split("Dr. Ali Raza Shah").given, "Dr. Ali Raza")
        XCTAssertEqual(PersonNameSplitter.split("Cher").given, "Cher")
        XCTAssertEqual(PersonNameSplitter.split("Cher").family, "")
    }
}
