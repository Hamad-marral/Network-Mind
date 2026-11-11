import AppIntents

/// Stops Event Mode without opening the app (Siri: "Stop Event Mode in NetworkMind").
struct StopEventModeIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Event Mode"
    static var description = IntentDescription("Stops recording and ends Event Mode.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard EventModeManager.shared.isActive else {
            return .result(dialog: "Event Mode is already off.")
        }
        EventModeManager.shared.stop(reason: .user)
        return .result(dialog: "Event Mode is off.")
    }
}

/// Shortcuts / Siri / Action Button entries.
struct NetworkMindShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: ToggleEventModeIntent(),
            phrases: [
                "Toggle Event Mode in \(.applicationName)",
                "Start Event Mode in \(.applicationName)",
                "Start \(.applicationName) Event Mode",
            ],
            shortTitle: "Event Mode",
            systemImageName: "mic.badge.plus"
        )
        AppShortcut(
            intent: StopEventModeIntent(),
            phrases: [
                "Stop Event Mode in \(.applicationName)",
                "Stop \(.applicationName) Event Mode",
            ],
            shortTitle: "Stop Event Mode",
            systemImageName: "stop.circle"
        )
    }
}
