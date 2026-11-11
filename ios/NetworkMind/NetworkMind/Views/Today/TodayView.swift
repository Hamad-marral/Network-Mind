import SwiftUI
import SwiftData

/// Daily Digest. M1: lists who was met today; later milestones add summaries,
/// opportunities, todos and drafts.
struct TodayView: View {
    @Query(sort: \Person.firstMetAt, order: .reverse) private var people: [Person]

    private var peopleMetToday: [Person] {
        people.filter { Calendar.current.isDateInToday($0.firstMetAt) }
    }

    var body: some View {
        NavigationStack {
            Group {
                if peopleMetToday.isEmpty {
                    ContentUnavailableView(
                        "No one yet today",
                        systemImage: "person.crop.circle.badge.plus",
                        description: Text("People you add or save to Contacts today will appear here with what you discussed.")
                    )
                } else {
                    List {
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
            }
            .navigationTitle("Today")
            .navigationDestination(for: Person.self) { PersonDetailView(person: $0) }
        }
    }
}
