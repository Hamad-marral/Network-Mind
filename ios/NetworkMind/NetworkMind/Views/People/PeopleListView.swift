import SwiftUI
import SwiftData

struct PeopleListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Person.firstMetAt, order: .reverse) private var people: [Person]
    @State private var searchText = ""

    private var filtered: [Person] {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return people }
        return people.filter { person in
            [person.name, person.company, person.title, person.notes, person.tags.joined(separator: " ")]
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if people.isEmpty {
                    ContentUnavailableView(
                        "No people yet",
                        systemImage: "person.2",
                        description: Text("New contacts you save, business cards you scan and people you add appear here.")
                    )
                } else if filtered.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                } else {
                    List {
                        ForEach(filtered) { person in
                            NavigationLink(value: person) { PersonRow(person: person) }
                        }
                        .onDelete(perform: delete)
                    }
                }
            }
            .navigationTitle("People")
            .searchable(text: $searchText, prompt: "Name, company, tag")
            .navigationDestination(for: Person.self) { PersonDetailView(person: $0) }
        }
    }

    private func delete(at offsets: IndexSet) {
        for index in offsets { modelContext.delete(filtered[index]) }
        try? modelContext.save()
    }
}

struct PersonRow: View {
    let person: Person

    var body: some View {
        HStack(spacing: 12) {
            AvatarView(initials: person.initials)
            VStack(alignment: .leading, spacing: 2) {
                Text(person.displayName).font(.headline)
                if !person.subtitle.isEmpty {
                    Text(person.subtitle).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(person.firstMetAt, format: .dateTime.month().day().hour().minute())
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if person.priority >= .high {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("High priority")
            }
        }
        .accessibilityElement(children: .combine)
    }
}
