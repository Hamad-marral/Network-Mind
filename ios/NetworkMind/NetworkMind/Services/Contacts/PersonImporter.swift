import Foundation
import SwiftData

/// Where/when context attached to newly detected people.
struct MeetingContext: Equatable, Sendable {
    var date: Date
    var latitude: Double?
    var longitude: Double?
    var placeName: String?
    var calendarEventTitle: String?
}

/// Creates `Person` records from contacts, deduplicating by `contactIdentifier`.
enum PersonImporter {
    /// Returns the persons that were created (existing ones are left untouched).
    @MainActor
    @discardableResult
    static func importContacts(
        _ contacts: [ContactSnapshot],
        context meetingContext: MeetingContext,
        source: PersonSource = .newContact,
        into modelContext: ModelContext
    ) throws -> [Person] {
        guard !contacts.isEmpty else { return [] }
        var known = try existingContactIdentifiers(in: modelContext)
        var created: [Person] = []
        for contact in contacts where !known.contains(contact.identifier) {
            let person = Person(
                name: contact.name,
                title: contact.jobTitle,
                company: contact.organization,
                phones: contact.phones,
                emails: contact.emails,
                contactIdentifier: contact.identifier,
                firstMetAt: meetingContext.date,
                source: source
            )
            person.metLatitude = meetingContext.latitude
            person.metLongitude = meetingContext.longitude
            person.metPlaceName = meetingContext.placeName
            person.matchedCalendarEventTitle = meetingContext.calendarEventTitle
            modelContext.insert(person)
            known.insert(contact.identifier)
            created.append(person)
        }
        if !created.isEmpty { try modelContext.save() }
        return created
    }

    @MainActor
    static func existingContactIdentifiers(in modelContext: ModelContext) throws -> Set<String> {
        let descriptor = FetchDescriptor<Person>(predicate: #Predicate { $0.contactIdentifier != nil })
        return Set(try modelContext.fetch(descriptor).compactMap(\.contactIdentifier))
    }
}
