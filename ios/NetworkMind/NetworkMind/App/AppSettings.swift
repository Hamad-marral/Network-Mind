import Foundation
import Combine

/// User preferences persisted in `UserDefaults`. Secrets (backend token) live in the
/// Keychain, never here.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    private let defaults: UserDefaults

    enum Key {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let hasAcceptedLegalConsent = "hasAcceptedLegalConsent"
        static let deleteAudioAfterTranscription = "deleteAudioAfterTranscription"
        static let allowServerRecognition = "allowServerRecognition"
        static let transcriptRetentionDays = "transcriptRetentionDays"
        static let eventModeAutoStopHours = "eventModeAutoStopHours"
        static let backendURL = "backendURL"
        static let tone = "tone"
        static let preferredLanguage = "preferredLanguage"
        static let defaultChannel = "defaultChannel"
        static let profileName = "profileName"
        static let profileRole = "profileRole"
        static let profileCompany = "profileCompany"
        static let profileOffers = "profileOffers"
        static let profileLookingFor = "profileLookingFor"
        static let notificationsEnabled = "notificationsEnabled"
        static let biometricLockEnabled = "biometricLockEnabled"
        static let cloudKitSyncEnabled = "cloudKitSyncEnabled"
        static let demoModeEnabled = "demoModeEnabled"
        static let autoProcessWhenCharging = "autoProcessWhenCharging"
        static let redactContactDetails = "redactContactDetails"
    }

    /// Default backend for local development (the FastAPI server in /backend).
    static let defaultBackendURL = "http://localhost:8000"

    @Published var hasCompletedOnboarding: Bool { didSet { defaults.set(hasCompletedOnboarding, forKey: Key.hasCompletedOnboarding) } }
    @Published var hasAcceptedLegalConsent: Bool { didSet { defaults.set(hasAcceptedLegalConsent, forKey: Key.hasAcceptedLegalConsent) } }
    @Published var deleteAudioAfterTranscription: Bool { didSet { defaults.set(deleteAudioAfterTranscription, forKey: Key.deleteAudioAfterTranscription) } }
    @Published var allowServerRecognition: Bool { didSet { defaults.set(allowServerRecognition, forKey: Key.allowServerRecognition) } }
    /// 0 = keep transcripts forever.
    @Published var transcriptRetentionDays: Int { didSet { defaults.set(transcriptRetentionDays, forKey: Key.transcriptRetentionDays) } }
    @Published var eventModeAutoStopHours: Double { didSet { defaults.set(eventModeAutoStopHours, forKey: Key.eventModeAutoStopHours) } }
    @Published var backendURL: String { didSet { defaults.set(backendURL, forKey: Key.backendURL) } }
    @Published var tone: FollowUpTone { didSet { defaults.set(tone.rawValue, forKey: Key.tone) } }
    /// "auto" = reply in the language of the conversation; otherwise "en", "ur", "ur-Latn".
    @Published var preferredLanguage: String { didSet { defaults.set(preferredLanguage, forKey: Key.preferredLanguage) } }
    @Published var defaultChannel: FollowUpChannel { didSet { defaults.set(defaultChannel.rawValue, forKey: Key.defaultChannel) } }
    @Published var profileName: String { didSet { defaults.set(profileName, forKey: Key.profileName) } }
    @Published var profileRole: String { didSet { defaults.set(profileRole, forKey: Key.profileRole) } }
    @Published var profileCompany: String { didSet { defaults.set(profileCompany, forKey: Key.profileCompany) } }
    @Published var profileOffers: String { didSet { defaults.set(profileOffers, forKey: Key.profileOffers) } }
    @Published var profileLookingFor: String { didSet { defaults.set(profileLookingFor, forKey: Key.profileLookingFor) } }
    @Published var notificationsEnabled: Bool { didSet { defaults.set(notificationsEnabled, forKey: Key.notificationsEnabled) } }
    @Published var biometricLockEnabled: Bool { didSet { defaults.set(biometricLockEnabled, forKey: Key.biometricLockEnabled) } }
    /// Takes effect on next launch (the container is built once).
    @Published var cloudKitSyncEnabled: Bool { didSet { defaults.set(cloudKitSyncEnabled, forKey: Key.cloudKitSyncEnabled) } }
    @Published var demoModeEnabled: Bool { didSet { defaults.set(demoModeEnabled, forKey: Key.demoModeEnabled) } }
    @Published var autoProcessWhenCharging: Bool { didSet { defaults.set(autoProcessWhenCharging, forKey: Key.autoProcessWhenCharging) } }
    @Published var redactContactDetails: Bool { didSet { defaults.set(redactContactDetails, forKey: Key.redactContactDetails) } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.deleteAudioAfterTranscription: true,
            Key.allowServerRecognition: false,
            Key.transcriptRetentionDays: 90,
            Key.eventModeAutoStopHours: 10.0,
            Key.backendURL: Self.defaultBackendURL,
            Key.tone: FollowUpTone.friendly.rawValue,
            Key.preferredLanguage: "auto",
            Key.defaultChannel: FollowUpChannel.whatsapp.rawValue,
            Key.notificationsEnabled: false,
            Key.biometricLockEnabled: false,
            Key.cloudKitSyncEnabled: false,
            Key.demoModeEnabled: false,
            Key.autoProcessWhenCharging: true,
            Key.redactContactDetails: true,
        ])
        hasCompletedOnboarding = defaults.bool(forKey: Key.hasCompletedOnboarding)
        hasAcceptedLegalConsent = defaults.bool(forKey: Key.hasAcceptedLegalConsent)
        deleteAudioAfterTranscription = defaults.bool(forKey: Key.deleteAudioAfterTranscription)
        allowServerRecognition = defaults.bool(forKey: Key.allowServerRecognition)
        transcriptRetentionDays = defaults.integer(forKey: Key.transcriptRetentionDays)
        eventModeAutoStopHours = defaults.double(forKey: Key.eventModeAutoStopHours)
        backendURL = defaults.string(forKey: Key.backendURL) ?? Self.defaultBackendURL
        tone = FollowUpTone(rawValue: defaults.string(forKey: Key.tone) ?? "") ?? .friendly
        preferredLanguage = defaults.string(forKey: Key.preferredLanguage) ?? "auto"
        defaultChannel = FollowUpChannel(rawValue: defaults.string(forKey: Key.defaultChannel) ?? "") ?? .whatsapp
        profileName = defaults.string(forKey: Key.profileName) ?? ""
        profileRole = defaults.string(forKey: Key.profileRole) ?? ""
        profileCompany = defaults.string(forKey: Key.profileCompany) ?? ""
        profileOffers = defaults.string(forKey: Key.profileOffers) ?? ""
        profileLookingFor = defaults.string(forKey: Key.profileLookingFor) ?? ""
        notificationsEnabled = defaults.bool(forKey: Key.notificationsEnabled)
        biometricLockEnabled = defaults.bool(forKey: Key.biometricLockEnabled)
        cloudKitSyncEnabled = defaults.bool(forKey: Key.cloudKitSyncEnabled)
        demoModeEnabled = defaults.bool(forKey: Key.demoModeEnabled)
        autoProcessWhenCharging = defaults.bool(forKey: Key.autoProcessWhenCharging)
        redactContactDetails = defaults.bool(forKey: Key.redactContactDetails)
    }

    /// Event Mode auto-stop interval in seconds (clamped to 15 min ... 24 h).
    var eventModeAutoStopInterval: TimeInterval {
        min(max(eventModeAutoStopHours, 0.25), 24) * 3600
    }

    /// Raw `UserDefaults` access for services that persist small state (e.g. contact
    /// history tokens) next to the settings.
    var store: UserDefaults { defaults }
}
