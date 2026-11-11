import Foundation
import ActivityKit
import AppIntents

// Compiled into BOTH the app and the widget extension. Intents declared here execute in
// the app process (LiveActivityIntent / openAppWhenRun), where the app has registered the
// handlers below at launch. In the extension the handlers are simply never set.

/// Live Activity shown while Event Mode is recording.
struct EventModeActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var isInterrupted: Bool
        var autoStopAt: Date
    }

    var startedAt: Date
}

/// Bridge from shared intents to the app's `EventModeManager`.
enum EventModeIntentBridge {
    @MainActor static var stopHandler: (@MainActor () async -> Void)?
    @MainActor static var toggleHandler: (@MainActor () async -> Void)?
}

/// "Stop" button on the Live Activity / Dynamic Island. Runs in the app process.
struct StopEventModeLiveActivityIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Stop Event Mode"
    static var description = IntentDescription("Stops recording and ends Event Mode.")

    init() {}

    func perform() async throws -> some IntentResult {
        if let handler = await EventModeIntentBridge.stopHandler {
            await handler()
        }
        return .result()
    }
}

/// Toggles Event Mode. Opens the app: stopping happens immediately, starting shows the
/// per-session consent confirmation (recording never starts without it).
/// Used by the Control Center / Lock Screen control, the Action Button and Shortcuts.
struct ToggleEventModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Toggle Event Mode"
    static var description = IntentDescription("Starts Event Mode (after you confirm you'll tell people you're taking notes) or stops it if it's running.")
    static var openAppWhenRun: Bool = true

    init() {}

    func perform() async throws -> some IntentResult {
        if let handler = await EventModeIntentBridge.toggleHandler {
            await handler()
        }
        return .result()
    }
}
