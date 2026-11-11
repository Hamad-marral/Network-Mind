import Foundation
import ActivityKit
import os

/// Starts/updates/ends the Event Mode Live Activity (elapsed time + Stop button).
@MainActor
enum EventModeLiveActivityController {
    private static let logger = Logger(subsystem: "com.networkmind.app", category: "LiveActivity")

    private static var current: Activity<EventModeActivityAttributes>? {
        Activity<EventModeActivityAttributes>.activities.first
    }

    static func start(startedAt: Date, autoStopAt: Date) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }
        endAll()
        let state = EventModeActivityAttributes.ContentState(isInterrupted: false, autoStopAt: autoStopAt)
        do {
            _ = try Activity.request(
                attributes: EventModeActivityAttributes(startedAt: startedAt),
                content: ActivityContent(state: state, staleDate: autoStopAt),
                pushType: nil
            )
        } catch {
            logger.error("Live Activity request failed: \(error.localizedDescription)")
        }
    }

    static func update(isInterrupted: Bool, autoStopAt: Date) {
        guard let activity = current else { return }
        let state = EventModeActivityAttributes.ContentState(isInterrupted: isInterrupted, autoStopAt: autoStopAt)
        Task { await activity.update(ActivityContent(state: state, staleDate: autoStopAt)) }
    }

    static func endAll() {
        for activity in Activity<EventModeActivityAttributes>.activities {
            Task { await activity.end(nil, dismissalPolicy: .immediate) }
        }
    }
}
