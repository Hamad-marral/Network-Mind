import Foundation
import Contacts

/// Plain snapshot of the contact fields NetworkMind uses.
struct ContactSnapshot: Equatable, Sendable {
    var identifier: String
    var name: String
    var jobTitle: String
    var organization: String
    var phones: [String]
    var emails: [String]
}

/// Input for creating a new Apple Contact.
struct NewContactInput: Equatable, Sendable {
    var name: String
    var jobTitle: String = ""
    var organization: String = ""
    var phone: String = ""
    var email: String = ""
}

/// Wraps `CNContactStore`. Contacts calls are synchronous and can be slow on large address
/// books; call from a background task.
final class ContactsService: ContactHistorySource, @unchecked Sendable {
    let store = CNContactStore()

    static var authorizationStatus: CNAuthorizationStatus {
        CNContactStore.authorizationStatus(for: .contacts)
    }

    /// Full access, or (iOS 18+) limited access to a user-chosen subset.
    static var hasAccess: Bool {
        let status = authorizationStatus
        if status == .authorized { return true }
        if #available(iOS 18.0, *), status == .limited { return true }
        return false
    }

    static var canRequestAccess: Bool { authorizationStatus == .notDetermined }

    func requestAccess() async -> Bool {
        do {
            return try await store.requestAccess(for: .contacts)
        } catch {
            return false
        }
    }

    // MARK: ContactHistorySource

    func currentHistoryToken() -> Data? {
        store.currentHistoryToken
    }

    func changes(since token: Data) throws -> (events: [ContactChangeEvent], token: Data?) {
        let result = try NMContactHistoryReader.fetchChanges(store: store, since: token)
        let events: [ContactChangeEvent] = result.changes.compactMap { change in
            switch change.kind {
            case .dropEverything: return .dropEverything
            case .added: return change.contactIdentifier.map(ContactChangeEvent.added)
            case .updated: return change.contactIdentifier.map(ContactChangeEvent.updated)
            case .deleted: return change.contactIdentifier.map(ContactChangeEvent.deleted)
            @unknown default: return nil
            }
        }
        return (events, result.currentHistoryToken)
    }

    func allContactIdentifiers() throws -> Set<String> {
        var ids = Set<String>()
        let request = CNContactFetchRequest(keysToFetch: [CNContactIdentifierKey as CNKeyDescriptor])
        request.unifyResults = true
        try store.enumerateContacts(with: request) { contact, _ in
            ids.insert(contact.identifier)
        }
        return ids
    }

    // MARK: Fetch & save

    private static let snapshotKeys: [CNKeyDescriptor] = [
        CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
        CNContactJobTitleKey as CNKeyDescriptor,
        CNContactOrganizationNameKey as CNKeyDescriptor,
        CNContactPhoneNumbersKey as CNKeyDescriptor,
        CNContactEmailAddressesKey as CNKeyDescriptor,
    ]

    func contacts(withIdentifiers identifiers: [String]) throws -> [ContactSnapshot] {
        guard !identifiers.isEmpty else { return [] }
        let predicate = CNContact.predicateForContacts(withIdentifiers: identifiers)
        let contacts = try store.unifiedContacts(matching: predicate, keysToFetch: Self.snapshotKeys)
        let byID = Dictionary(contacts.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        // Preserve the caller's order (history order ≈ the order people were met).
        return identifiers.compactMap { byID[$0].map(Self.snapshot) }
    }

    /// Creates an Apple Contact and returns its identifier.
    func saveNewContact(_ input: NewContactInput) throws -> String {
        let contact = CNMutableContact()
        let nameParts = PersonNameSplitter.split(input.name)
        contact.givenName = nameParts.given
        contact.familyName = nameParts.family
        contact.jobTitle = input.jobTitle
        contact.organizationName = input.organization
        if !input.phone.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMobile, value: CNPhoneNumber(stringValue: input.phone))]
        }
        if !input.email.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: input.email as NSString)]
        }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        try store.execute(request)
        return contact.identifier
    }

    static func snapshot(from contact: CNContact) -> ContactSnapshot {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
        let name = formatted.isEmpty ? contact.organizationName : formatted
        return ContactSnapshot(
            identifier: contact.identifier,
            name: name,
            jobTitle: contact.jobTitle,
            organization: contact.organizationName,
            phones: contact.phoneNumbers.map { $0.value.stringValue },
            emails: contact.emailAddresses.map { $0.value as String }
        )
    }
}

enum PersonNameSplitter {
    /// "Ayesha Khan" → ("Ayesha", "Khan"); "Dr. Ali Raza Shah" → ("Dr. Ali Raza", "Shah").
    static func split(_ name: String) -> (given: String, family: String) {
        let parts = name.split(whereSeparator: \.isWhitespace).map(String.init)
        guard parts.count > 1 else { return (parts.first ?? "", "") }
        return (parts.dropLast().joined(separator: " "), parts.last ?? "")
    }
}
