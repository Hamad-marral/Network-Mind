import Foundation
import SwiftData
import os

/// Builds the app's SwiftData container.
enum DataStore {
    static let models: [any PersistentModel.Type] = [
        Person.self,
        Meeting.self,
        RecordingSession.self,
        RecordingChunk.self,
        Opportunity.self,
        TodoItem.self,
        FollowUpDraft.self,
        ConsentRecord.self,
    ]

    static var schema: Schema { Schema(models) }

    private static let logger = Logger(subsystem: "com.networkmind.app", category: "DataStore")

    /// The persistent container. CloudKit sync is opt-in (Settings flag, requires the iCloud
    /// capability with a CloudKit container); if CloudKit cannot be configured we fall back
    /// to a local-only store so the app always launches.
    static func makeContainer(cloudKitEnabled: Bool = AppSettings.shared.cloudKitSyncEnabled) -> ModelContainer {
        if cloudKitEnabled {
            do {
                let config = ModelConfiguration(schema: schema, cloudKitDatabase: .automatic)
                return try ModelContainer(for: schema, configurations: config)
            } catch {
                logger.error("CloudKit container unavailable, using local store: \(error.localizedDescription)")
            }
        }
        do {
            let config = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            // A corrupted or unmigratable store must not brick the app; fall back to memory
            // and surface the problem in the log.
            logger.fault("Persistent store failed to open: \(error.localizedDescription)")
            return makeInMemoryContainer()
        }
    }

    static func makeInMemoryContainer() -> ModelContainer {
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            fatalError("In-memory SwiftData container failed: \(error)")
        }
    }
}
