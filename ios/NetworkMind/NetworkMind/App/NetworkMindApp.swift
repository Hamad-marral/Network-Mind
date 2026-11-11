import SwiftUI
import SwiftData

@main
struct NetworkMindApp: App {
    @StateObject private var settings = AppSettings.shared
    @Environment(\.scenePhase) private var scenePhase
    private let container: ModelContainer

    init() {
        // UI tests launch with an in-memory store so they never touch real data.
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            container = DataStore.makeInMemoryContainer()
        } else {
            container = DataStore.makeContainer()
        }
        ContactDetectionService.shared.configure(container: container)
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
        }
        .modelContainer(container)
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                // Covers both cold launch and returning to the foreground.
                Task { await ContactDetectionService.shared.sync(trigger: .foreground) }
            case .background:
                ContactDetectionService.scheduleBackgroundRefresh()
            default:
                break
            }
        }
        .backgroundTask(.appRefresh(ContactDetectionService.refreshTaskIdentifier)) {
            await ContactDetectionService.scheduleBackgroundRefresh()
            await ContactDetectionService.shared.sync(trigger: .backgroundRefresh)
        }
    }
}
