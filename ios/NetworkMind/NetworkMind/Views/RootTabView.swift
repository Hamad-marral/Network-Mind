import SwiftUI

enum AppTab: Hashable {
    case today, people, sessions, settings
}

struct RootTabView: View {
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
    }
}
