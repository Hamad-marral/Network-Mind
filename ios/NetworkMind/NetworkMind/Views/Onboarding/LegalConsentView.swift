import SwiftUI
import SwiftData

/// First-launch notice about recording laws and how NetworkMind handles audio. The user
/// must acknowledge it before using the app; the acknowledgment is stored with a timestamp.
struct LegalConsentView: View {
    @Environment(\.modelContext) private var modelContext
    @EnvironmentObject private var settings: AppSettings
    @State private var understood = false

    static let consentText = """
    I understand that recording conversations may require the consent of everyone being recorded \
    (two-party or all-party consent) depending on where I am. I am responsible for following the \
    laws that apply to me and for telling people when I am recording for notes.
    """

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityHidden(true)
                    Text("Before you start")
                        .font(.largeTitle.bold())

                    ConsentPoint(
                        systemImage: "mic.fill",
                        title: "Recording only when you turn it on",
                        text: "NetworkMind records audio only while Event Mode is on. iOS shows the orange microphone indicator the whole time, and the app shows a banner. You turn it off, or it stops by itself after a time you choose."
                    )
                    ConsentPoint(
                        systemImage: "building.columns.fill",
                        title: "Recording laws differ by place",
                        text: "Many places require consent from everyone in a conversation before it is recorded (for example, several US states and many countries). Others require at least one participant's consent. Always tell people you're recording for notes, and don't record where it isn't allowed."
                    )
                    ConsentPoint(
                        systemImage: "lock.iphone",
                        title: "Audio stays on your phone",
                        text: "Speech is transcribed on your device when possible. Audio is never uploaded, and by default it's deleted after transcription. Only transcript text is sent to your NetworkMind server to create summaries and follow-up drafts. It is processed there but not stored."
                    )
                    ConsentPoint(
                        systemImage: "trash.fill",
                        title: "You're in control",
                        text: "Delete any person, meeting or session at any time, or delete everything from Settings."
                    )

                    Toggle(isOn: $understood) {
                        Text(Self.consentText).font(.callout)
                    }
                    .toggleStyle(CheckboxToggleStyle())
                    .padding()
                    .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))

                    Button {
                        accept()
                    } label: {
                        Text("Agree and continue")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(!understood)
                    .accessibilityIdentifier("legalAgreeButton")
                }
                .padding()
            }
            .interactiveDismissDisabled()
        }
    }

    private func accept() {
        modelContext.insert(ConsentRecord(kind: .legalTerms, text: Self.consentText))
        try? modelContext.save()
        settings.hasAcceptedLegalConsent = true
    }
}

private struct ConsentPoint: View {
    let systemImage: String
    let title: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Color.accentColor)
                .frame(width: 30)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Checkbox-style toggle (square, tappable label).
struct CheckboxToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: configuration.isOn ? "checkmark.square.fill" : "square")
                    .font(.title2)
                    .foregroundStyle(configuration.isOn ? Color.accentColor : .secondary)
                configuration.label
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.leading)
            }
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(configuration.isOn ? [.isButton, .isSelected] : .isButton)
    }
}
