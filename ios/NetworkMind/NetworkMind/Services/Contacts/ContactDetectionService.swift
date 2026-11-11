import Foundation
import Contacts
import SwiftData
import BackgroundTasks
import os

/// Detects contacts added to Apple Contacts (e.g. after exchanging details in person) and
/// turns them into `Person` records with time, place and calendar context.
///
/// There is no NameDrop API: we only observe that a contact appeared, so new people are
/// labelled "New contact". Triggers: launch, foreground, `CNContactStoreDidChange`, and a
/// `BGAppRefreshTask`.
@MainActor
final class ContactDetectionService: ObservableObject {
    static let shared = ContactDetectionService()
    static let refreshTaskIdentifier = "com.networkmind.app.contacts-refresh"

    enum Trigger: String {
        case launch, foreground, storeChanged, backgroundRefresh, manual
    }

    @Published private(set) var hasAccess = ContactsService.hasAccess
    @Published private(set) var isSyncing = false
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var lastImportCount = 0

    private let contacts = ContactsService()
    private let state = DefaultsContactSyncStateStore()
    private var container: ModelContainer?
    private var observer: NSObjectProtocol?
    private var debounceTask: Task<Void, Never>?
    private let logger = Logger(subsystem: "com.networkmind.app", category: "ContactDetection")

    func configure(container: ModelContainer) {
        self.container = container
        guard observer == nil else { return }
        observer = NotificationCenter.default.addObserver(
            forName: .CNContactStoreDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.scheduleDebouncedSync() }
        }
    }

    func refreshAuthorization() {
        hasAccess = ContactsService.hasAccess
    }

    func requestAccess() async -> Bool {
        let granted = await contacts.requestAccess()
        refreshAuthorization()
        if granted { await sync(trigger: .manual) }
        return granted
    }

    /// The notification fires several times per edit (and for our own saves); coalesce.
    private func scheduleDebouncedSync() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(1.5))
            guard !Task.isCancelled else { return }
            await self?.sync(trigger: .storeChanged)
        }
    }

    /// Runs one detection pass. Returns the number of people created.
    @discardableResult
    func sync(trigger: Trigger) async -> Int {
        refreshAuthorization()
        guard hasAccess, let container, !isSyncing else { return 0 }
        isSyncing = true
        defer { isSyncing = false }

        let detectedAt = Date()
        let contacts = self.contacts
        let state = self.state
        do {
            // Contacts I/O off the main thread.
            let snapshots: [ContactSnapshot] = try await Task.detached(priority: .utility) {
                let outcome = try ContactChangeEngine(source: contacts, state: state).detectNewContacts()
                return try contacts.contacts(withIdentifiers: outcome.newIdentifiers)
            }.value

            let modelContext = container.mainContext
            let known = try PersonImporter.existingContactIdentifiers(in: modelContext)
            let fresh = snapshots.filter { !known.contains($0.identifier) }
            guard !fresh.isEmpty else {
                finish(count: 0)
                return 0
            }

            let meetingContext = await gatherContext(at: detectedAt, includeLocation: trigger != .backgroundRefresh)
            let created = try PersonImporter.importContacts(fresh, context: meetingContext, into: modelContext)
            logger.info("Imported \(created.count) new contact(s) via \(trigger.rawValue)")
            finish(count: created.count)
            return created.count
        } catch {
            logger.error("Contact sync failed: \(error.localizedDescription)")
            lastError = error.localizedDescription
            return 0
        }
    }

    private func finish(count: Int) {
        lastSyncAt = Date()
        lastError = nil
        lastImportCount = count
    }

    /// Location (one fix, only while the app can get one) + overlapping calendar event.
    private func gatherContext(at date: Date, includeLocation: Bool) async -> MeetingContext {
        var context = MeetingContext(date: date)
        if includeLocation, let location = await LocationService.shared.currentLocation() {
            context.latitude = location.coordinate.latitude
            context.longitude = location.coordinate.longitude
            context.placeName = await LocationService.shared.placeName(for: location)
        }
        context.calendarEventTitle = CalendarService.shared.eventTitle(overlapping: date)
        return context
    }

    /// Forget the token and snapshot (used by "Delete all data").
    func resetSyncState() {
        state.reset()
    }

    // MARK: Background refresh

    static func scheduleBackgroundRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskIdentifier)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 15 * 60)
        do {
            try BGTaskScheduler.shared.submit(request)
        } catch {
            // Expected in the simulator and when Background App Refresh is disabled.
            Logger(subsystem: "com.networkmind.app", category: "ContactDetection")
                .debug("BGAppRefresh not scheduled: \(error.localizedDescription)")
        }
    }
}
