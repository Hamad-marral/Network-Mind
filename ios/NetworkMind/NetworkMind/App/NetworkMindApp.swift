import SwiftUI
import SwiftData

@main
struct NetworkMindApp: App {
    @StateObject private var settings = AppSettings.shared
    private let container: ModelContainer

    init() {
        // UI tests launch with an in-memory store so they never touch real data.
        if ProcessInfo.processInfo.arguments.contains("-uiTesting") {
            container = DataStore.makeInMemoryContainer()
        } else {
            container = DataStore.makeContainer()
        }
    }

    var body: some Scene {
        WindowGroup {
            RootTabView()
                .environmentObject(settings)
        }
        .modelContainer(container)
    }
}
