import Foundation
import SwiftData

/// Someone the user met. Created from a new Apple Contact, a scanned business card,
/// a manual entry, or demo data. Deduplicated by `contactIdentifier` in code (CloudKit
/// does not allow unique constraints).
@Model
final class Person {
    var id: UUID = UUID()
    var name: String = ""
    var title: String = ""
    var company: String = ""
    var phones: [String] = []
    var emails: [String] = []
    /// `CNContact.identifier` of the linked Apple Contact, if any.
    var contactIdentifier: String?

    var firstMetAt: Date = Date()
    var metLatitude: Double?
    var metLongitude: Double?
    /// Reverse-geocoded place name ("Expo Centre, Lahore").
    var metPlaceName: String?
    /// Title of the calendar event overlapping `firstMetAt`, if any.
    var matchedCalendarEventTitle: String?

    var tags: [String] = []
    var notes: String = ""
    var priorityRaw: Int = Priority.normal.rawValue
    var lastContactedAt: Date?
    var nextFollowUpAt: Date?
    /// Personal details worth remembering, accumulated from analyses.
    var keyFacts: [String] = []
    var sourceRaw: String = PersonSource.manual.rawValue
    var createdAt: Date = Date()

    @Relationship(deleteRule: .nullify, inverse: \Meeting.person)
    var meetings: [Meeting]? = []

    @Relationship(deleteRule: .nullify, inverse: \FollowUpDraft.person)
    var followUpDrafts: [FollowUpDraft]? = []

    init(
        name: String,
        title: String = "",
        company: String = "",
        phones: [String] = [],
        emails: [String] = [],
        contactIdentifier: String? = nil,
        firstMetAt: Date = Date(),
        source: PersonSource = .manual
    ) {
        self.id = UUID()
        self.name = name
        self.title = title
        self.company = company
        self.phones = phones
        self.emails = emails
        self.contactIdentifier = contactIdentifier
        self.firstMetAt = firstMetAt
        self.sourceRaw = source.rawValue
        self.createdAt = Date()
    }

    var priority: Priority {
        get { Priority(rawValue: priorityRaw) ?? .normal }
        set { priorityRaw = newValue.rawValue }
    }

    var source: PersonSource {
        get { PersonSource(rawValue: sourceRaw) ?? .manual }
        set { sourceRaw = newValue.rawValue }
    }

    var hasLocation: Bool { metLatitude != nil && metLongitude != nil }

    var displayName: String { name.isEmpty ? "Unnamed contact" : name }

    /// "Title · Company", omitting empty parts.
    var subtitle: String {
        [title, company].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    var initials: String {
        let parts = displayName.split(separator: " ").prefix(2)
        let letters = parts.compactMap { $0.first.map(String.init) }.joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }

    var sortedMeetings: [Meeting] {
        (meetings ?? []).sorted { $0.startedAt > $1.startedAt }
    }
}
