import Foundation
import EventKit

/// Minimal event description used for matching (decoupled from EventKit for tests).
struct CalendarEventInfo: Equatable, Sendable {
    var title: String
    var start: Date
    var end: Date
    var isAllDay: Bool
}

enum CalendarEventMatcher {
    /// The event the user was most likely attending at `date`: a timed (not all-day) event
    /// that contains `date` (with a small tolerance for arriving early / leaving late),
    /// preferring the shortest such event (a talk inside a conference block).
    static func bestMatch(for date: Date, in events: [CalendarEventInfo], tolerance: TimeInterval = 10 * 60) -> CalendarEventInfo? {
        events
            .filter { !$0.isAllDay && !$0.title.isEmpty }
            .filter { $0.start.addingTimeInterval(-tolerance) <= date && date <= $0.end.addingTimeInterval(tolerance) }
            .min { lhs, rhs in
                let lhsContains = lhs.start <= date && date <= lhs.end
                let rhsContains = rhs.start <= date && date <= rhs.end
                if lhsContains != rhsContains { return lhsContains }
                return lhs.end.timeIntervalSince(lhs.start) < rhs.end.timeIntervalSince(rhs.start)
            }
    }
}

/// Reads the calendar (read-only) to label where someone was met.
final class CalendarService: @unchecked Sendable {
    static let shared = CalendarService()

    private let store = EKEventStore()

    static var hasAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .fullAccess
    }

    static var canRequestAccess: Bool {
        EKEventStore.authorizationStatus(for: .event) == .notDetermined
    }

    func requestAccess() async -> Bool {
        (try? await store.requestFullAccessToEvents()) ?? false
    }

    func eventTitle(overlapping date: Date) -> String? {
        guard Self.hasAccess else { return nil }
        let predicate = store.predicateForEvents(
            withStart: date.addingTimeInterval(-12 * 3600),
            end: date.addingTimeInterval(12 * 3600),
            calendars: nil
        )
        let events = store.events(matching: predicate).map {
            CalendarEventInfo(title: $0.title ?? "", start: $0.startDate, end: $0.endDate, isAllDay: $0.isAllDay)
        }
        return CalendarEventMatcher.bestMatch(for: date, in: events)?.title
    }
}
