import SwiftUI
import SwiftData

struct PersonDetailView: View {
    @Bindable var person: Person
    @State private var newTag = ""

    var body: some View {
        Form {
            Section {
                HStack(spacing: 16) {
                    AvatarView(initials: person.initials, size: 64)
                    VStack(alignment: .leading) {
                        Text(person.displayName).font(.title2.bold())
                        if !person.subtitle.isEmpty {
                            Text(person.subtitle).foregroundStyle(.secondary)
                        }
                        TagChip(text: person.source.label, color: .secondary)
                    }
                }
                .listRowBackground(Color.clear)
            }

            Section("Details") {
                TextField("Name", text: $person.name)
                TextField("Title", text: $person.title)
                TextField("Company", text: $person.company)
                Picker("Priority", selection: Binding(get: { person.priority }, set: { person.priority = $0 })) {
                    ForEach(Priority.allCases) { Text($0.label).tag($0) }
                }
            }

            Section("Met") {
                LabeledContent("When", value: person.firstMetAt.formatted(date: .abbreviated, time: .shortened))
                if let place = person.metPlaceName {
                    LabeledContent("Where", value: place)
                }
                if let event = person.matchedCalendarEventTitle {
                    LabeledContent("Event", value: event)
                }
            }

            if !person.phones.isEmpty || !person.emails.isEmpty {
                Section("Contact") {
                    ForEach(person.phones, id: \.self) { Label($0, systemImage: "phone") }
                    ForEach(person.emails, id: \.self) { Label($0, systemImage: "envelope") }
                }
            }

            Section("Tags") {
                if !person.tags.isEmpty {
                    ForEach(person.tags, id: \.self) { Text($0) }
                        .onDelete { person.tags.remove(atOffsets: $0) }
                }
                HStack {
                    TextField("Add tag", text: $newTag)
                        .onSubmit(addTag)
                    Button("Add", action: addTag)
                        .disabled(newTag.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Notes") {
                TextField("Notes", text: $person.notes, axis: .vertical)
                    .lineLimit(3...10)
            }

            if !person.keyFacts.isEmpty {
                Section("Worth remembering") {
                    ForEach(person.keyFacts, id: \.self) { Text($0) }
                }
            }
        }
        .navigationTitle(person.displayName)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func addTag() {
        let tag = newTag.trimmingCharacters(in: .whitespaces)
        guard !tag.isEmpty, !person.tags.contains(tag) else { return }
        person.tags.append(tag)
        newTag = ""
    }
}
