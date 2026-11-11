import SwiftUI

enum AppTab: Hashable {
    case today, people, sessions, settings
}

struct RootTabView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var eventMode = EventModeManager.shared
    @State private var selection: AppTab = .today

    var body: some View {
        TabView(selection: $selection) {
            TodayView()
                .tabItem { Label("Today", systemImage: "sun.max") }
                .tag(AppTab.today)
            PeopleListView()
                .tabItem { Label("People", systemImage: "person.2") }
                .tag(AppTab.people)
            SessionsListView()
                .tabItem { Label("Sessions", systemImage: "waveform") }
                .tag(AppTab.sessions)
            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(AppTab.settings)
        }
        .safeAreaInset(edge: .top, spacing: 0) { EventModeBanner() }
        .sheet(isPresented: $eventMode.pendingStartRequest) {
            EventModeConsentSheet()
        }
        .fullScreenCover(isPresented: Binding(
            get: { !settings.hasAcceptedLegalConsent },
            set: { _ in }
        )) {
            LegalConsentView()
        }
        .onOpenURL(perform: handleDeepLink)
    }

    /// networkmind://event-mode/toggle (also used by docs/automation).
    private func handleDeepLink(_ url: URL) {
        guard url.scheme == "networkmind" else { return }
        if url.host == "event-mode" {
            selection = .today
            eventMode.toggleFromShortcut()
        }
    }
}
