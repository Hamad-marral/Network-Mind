import SwiftUI
import CoreLocation

/// Explains why NetworkMind wants Contacts (required for detection), Location and Calendar
/// (optional enrichment) and requests each only when the user taps its button.
struct ContactDetectionSetupView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var detection = ContactDetectionService.shared
    @ObservedObject private var location = LocationService.shared
    @State private var calendarGranted = CalendarService.hasAccess
    @State private var calendarAsked = !CalendarService.canRequestAccess

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 44))
                            .foregroundStyle(Color.accentColor)
                            .accessibilityHidden(true)
                        Text("Remember everyone you meet")
                            .font(.title2.bold())
                        Text("When you save someone's details — by exchanging contacts, typing them in, or any other way — NetworkMind notices the new contact and records when (and optionally where) you met.")
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                Section {
                    PermissionRow(
                        title: "Contacts",
                        detail: "Required. Read only to detect newly added contacts. Your address book never leaves your device.",
                        systemImage: "person.2.fill",
                        state: detection.hasAccess ? .granted : (ContactsService.canRequestAccess ? .ask : .denied)
                    ) {
                        Task { _ = await detection.requestAccess() }
                    }
                    PermissionRow(
                        title: "Location (optional)",
                        detail: "Tags the place you met, e.g. \"Expo Centre\". Only while you use the app; one quick fix per new contact.",
                        systemImage: "location.fill",
                        state: location.isAuthorized ? .granted : (location.canRequestAuthorization ? .ask : .denied)
                    ) {
                        location.requestAuthorization()
                    }
                    PermissionRow(
                        title: "Calendar (optional)",
                        detail: "Matches the event you were at, e.g. \"Fintech Summit\". Read only.",
                        systemImage: "calendar",
                        state: calendarGranted ? .granted : (calendarAsked ? .denied : .ask)
                    ) {
                        Task {
                            calendarGranted = await CalendarService.shared.requestAccess()
                            calendarAsked = true
                        }
                    }
                } footer: {
                    Text("You can change these anytime in the iOS Settings app. NetworkMind works without them; you can always add people manually or scan a business card.")
                }
            }
            .navigationTitle("Contact detection")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}

struct PermissionRow: View {
    enum Status { case ask, granted, denied }

    let title: String
    let detail: String
    let systemImage: String
    let state: Status
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .frame(width: 28)
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
                switch state {
                case .ask:
                    Button("Allow", action: action)
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                case .granted:
                    Label("Allowed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green)
                        .font(.subheadline)
                case .denied:
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .font(.subheadline)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
