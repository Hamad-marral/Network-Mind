import SwiftUI
import SwiftData

/// Daily Digest. Lists who was met today; later milestones add summaries,
/// opportunities, todos and drafts.
struct TodayView: View {
    @Query(sort: \Person.firstMetAt, order: .reverse) private var people: [Person]
    @ObservedObject private var detection = ContactDetectionService.shared

    private var peopleMetToday: [Person] {
        people.filter { Calendar.current.isDateInToday($0.firstMetAt) }
    }

    var body: some View {
        NavigationStack {
            List {
                Section { EventModeCard() }
                if !detection.hasAccess {
                    Section { ContactDetectionPromptCard() }
                }
                if peopleMetToday.isEmpty {
                    Section {
                        ContentUnavailableView(
                            "No one yet today",
                            systemImage: "person.crop.circle.badge.plus",
                            description: Text("People you add or save to Contacts today will appear here with what you discussed.")
                        )
                    }
                    .listRowBackground(Color.clear)
                } else {
                    Section {
                        ForEach(peopleMetToday) { person in
                            NavigationLink(value: person) {
                                PersonRow(person: person)
                            }
                        }
                    } header: {
                        Text("You met \(peopleMetToday.count) \(peopleMetToday.count == 1 ? "person" : "people") today")
                    }
                }
            }
            .refreshable { await detection.sync(trigger: .manual) }
            .navigationTitle("Today")
            .navigationDestination(for: Person.self) { PersonDetailView(person: $0) }
            .toolbar {
                ToolbarItem(placement: .primaryAction) { AddPersonMenu() }
            }
        }
    }
}
