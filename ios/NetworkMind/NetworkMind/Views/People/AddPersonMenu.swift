import SwiftUI

/// Toolbar "+" menu: add a person manually or scan a business card.
struct AddPersonMenu: View {
    enum Sheet: String, Identifiable {
        case manual, scan
        var id: String { rawValue }
    }

    @State private var sheet: Sheet?

    var body: some View {
        Menu {
            Button { sheet = .manual } label: { Label("Add person", systemImage: "person.badge.plus") }
            Button { sheet = .scan } label: { Label("Scan business card", systemImage: "text.viewfinder") }
        } label: {
            Image(systemName: "plus")
                .accessibilityLabel("Add person")
        }
        .sheet(item: $sheet) { sheet in
            switch sheet {
            case .manual: AddPersonView()
            case .scan: BusinessCardScanFlow()
            }
        }
    }
}

/// Card prompting the user to turn on contact detection (shown until access is granted).
struct ContactDetectionPromptCard: View {
    @ObservedObject private var detection = ContactDetectionService.shared
    @State private var showingSetup = false

    var body: some View {
        if !detection.hasAccess {
            VStack(alignment: .leading, spacing: 8) {
                Label("Detect new contacts automatically", systemImage: "person.crop.circle.badge.plus")
                    .font(.headline)
                Text("When you save someone's number, NetworkMind remembers when and where you met.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Button("Set up") { showingSetup = true }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
            .sheet(isPresented: $showingSetup) { ContactDetectionSetupView() }
        }
    }
}
