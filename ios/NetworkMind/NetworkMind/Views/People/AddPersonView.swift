import SwiftUI
import SwiftData

/// Quick form to add a person manually or confirm a scanned business card.
struct AddPersonView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    var source: PersonSource = .manual
    @State var input: NewContactInput
    @State private var notes = ""
    @State private var saveToContacts = ContactsService.hasAccess
    @State private var errorMessage: String?
    @State private var isSaving = false

    init(prefill: NewContactInput = NewContactInput(name: ""), source: PersonSource = .manual) {
        self.source = source
        _input = State(initialValue: prefill)
    }

    private var canSave: Bool {
        !input.name.trimmingCharacters(in: .whitespaces).isEmpty && !isSaving
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $input.name)
                        .textContentType(.name)
                    TextField("Title", text: $input.jobTitle)
                        .textContentType(.jobTitle)
                    TextField("Company", text: $input.organization)
                        .textContentType(.organizationName)
                }
                Section {
                    TextField("Phone", text: $input.phone)
                        .keyboardType(.phonePad)
                        .textContentType(.telephoneNumber)
                    TextField("Email", text: $input.email)
                        .keyboardType(.emailAddress)
                        .textContentType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    TextField("Notes (optional)", text: $notes, axis: .vertical)
                        .lineLimit(2...6)
                }
                Section {
                    Toggle("Also save to Contacts", isOn: $saveToContacts)
                        .disabled(!ContactsService.hasAccess)
                } footer: {
                    if !ContactsService.hasAccess {
                        Text("Allow Contacts access in Settings to save to your address book.")
                    }
                }
                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .navigationTitle(source == .businessCard ? "Business card" : "Add person")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { Task { await save() } }
                        .disabled(!canSave)
                }
            }
        }
    }

    private func save() async {
        isSaving = true
        defer { isSaving = false }
        var cleaned = input
        cleaned.name = cleaned.name.trimmingCharacters(in: .whitespaces)
        cleaned.email = cleaned.email.trimmingCharacters(in: .whitespaces)
        cleaned.phone = cleaned.phone.trimmingCharacters(in: .whitespaces)

        var contactIdentifier: String?
        if saveToContacts && ContactsService.hasAccess {
            do {
                let toSave = cleaned
                contactIdentifier = try await Task.detached { try ContactsService().saveNewContact(toSave) }.value
            } catch {
                errorMessage = "Couldn't save to Contacts: \(error.localizedDescription)"
                return
            }
        }

        let person = Person(
            name: cleaned.name,
            title: cleaned.jobTitle,
            company: cleaned.organization,
            phones: cleaned.phone.isEmpty ? [] : [cleaned.phone],
            emails: cleaned.email.isEmpty ? [] : [cleaned.email],
            contactIdentifier: contactIdentifier,
            firstMetAt: Date(),
            source: source
        )
        person.notes = notes
        modelContext.insert(person)
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
            return
        }
        // Context (place, event) is best-effort and must not block the form.
        Task { await PersonContextEnricher.enrich(person) }
        dismiss()
    }
}

/// Adds location/calendar context to a manually created person.
enum PersonContextEnricher {
    @MainActor
    static func enrich(_ person: Person) async {
        if let title = CalendarService.shared.eventTitle(overlapping: person.firstMetAt) {
            person.matchedCalendarEventTitle = title
        }
        if let location = await LocationService.shared.currentLocation() {
            person.metLatitude = location.coordinate.latitude
            person.metLongitude = location.coordinate.longitude
            person.metPlaceName = await LocationService.shared.placeName(for: location)
        }
        try? person.modelContext?.save()
    }
}
