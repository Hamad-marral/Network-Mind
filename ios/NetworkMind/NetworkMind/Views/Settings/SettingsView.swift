import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var settings: AppSettings
    @ObservedObject private var detection = ContactDetectionService.shared
    @State private var showingContactSetup = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Contact detection") {
                    Button {
                        showingContactSetup = true
                    } label: {
                        LabeledContent("Contacts, location & calendar", value: detection.hasAccess ? "On" : "Off")
                    }
                    if let last = detection.lastSyncAt {
                        LabeledContent("Last checked", value: last.formatted(date: .omitted, time: .shortened))
                    }
                    if let error = detection.lastError {
                        Text(error).font(.footnote).foregroundStyle(.red)
                    }
                }

                Section {
                    TextField("Your name", text: $settings.profileName)
                    TextField("Role", text: $settings.profileRole)
                    TextField("Company", text: $settings.profileCompany)
                    TextField("What I offer", text: $settings.profileOffers, axis: .vertical)
                    TextField("What I'm looking for", text: $settings.profileLookingFor, axis: .vertical)
                } header: {
                    Text("My profile & goals")
                } footer: {
                    Text("Used to spot opportunities that matter to you.")
                }

                Section("Recording & privacy") {
                    Toggle("Delete audio after transcription", isOn: $settings.deleteAudioAfterTranscription)
                    Stepper(value: $settings.eventModeAutoStopHours, in: 1...24, step: 1) {
                        LabeledContent("Event Mode auto-stop", value: "\(Int(settings.eventModeAutoStopHours)) h")
                    }
                }

                Section("Follow-ups") {
                    Picker("Tone", selection: $settings.tone) {
                        ForEach(FollowUpTone.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Default channel", selection: $settings.defaultChannel) {
                        ForEach(FollowUpChannel.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section("Backend") {
                    TextField("Backend URL", text: $settings.backendURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingContactSetup) { ContactDetectionSetupView() }
        }
    }
}
