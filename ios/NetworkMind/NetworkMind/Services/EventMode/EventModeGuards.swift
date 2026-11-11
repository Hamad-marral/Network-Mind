import Foundation

enum EventModeStopReason: String, Codable, Sendable {
    case user
    case autoStop
    case lowBattery
    case lowStorage
    case crashRecovery
    case error

    var message: String {
        switch self {
        case .user: "Event Mode turned off."
        case .autoStop: "Event Mode stopped automatically after the time limit."
        case .lowBattery: "Event Mode stopped because the battery is below 10%."
        case .lowStorage: "Event Mode stopped because the device is almost out of storage."
        case .crashRecovery: "The last Event Mode session ended unexpectedly. Recorded audio was kept."
        case .error: "Event Mode stopped because of a recording error."
        }
    }
}

/// Inputs for one guard evaluation (sampled from the device).
struct DeviceConditions: Equatable, Sendable {
    /// 0...1, or a negative value when unknown (simulator / monitoring off).
    var batteryLevel: Float
    var isCharging: Bool
    /// Bytes available for important usage, or nil when unknown.
    var freeBytes: Int64?
}

/// Pure decision logic for Event Mode safety limits.
enum EventModeGuards {
    static let stopBatteryLevel: Float = 0.10
    static let warnBatteryLevel: Float = 0.20
    static let stopFreeBytes: Int64 = 200 * 1024 * 1024
    static let warnFreeBytes: Int64 = 1024 * 1024 * 1024

    enum Decision: Equatable {
        case ok
        case warn(String)
        case stop(EventModeStopReason)
    }

    static func evaluate(conditions: DeviceConditions, now: Date, autoStopAt: Date?) -> Decision {
        if let autoStopAt, now >= autoStopAt {
            return .stop(.autoStop)
        }
        let batteryKnown = conditions.batteryLevel >= 0
        if batteryKnown, !conditions.isCharging, conditions.batteryLevel < stopBatteryLevel {
            return .stop(.lowBattery)
        }
        if let free = conditions.freeBytes, free < stopFreeBytes {
            return .stop(.lowStorage)
        }
        if batteryKnown, !conditions.isCharging, conditions.batteryLevel < warnBatteryLevel {
            return .warn("Battery is low (\(Int(conditions.batteryLevel * 100))%). Event Mode will stop at 10% unless you plug in.")
        }
        if let free = conditions.freeBytes, free < warnFreeBytes {
            return .warn("Storage is running low. Event Mode will stop if less than 200 MB remain.")
        }
        return .ok
    }

    /// Whether Event Mode may start right now (same limits as `evaluate`, minus auto-stop).
    static func canStart(conditions: DeviceConditions) -> EventModeStopReason? {
        switch evaluate(conditions: conditions, now: Date(), autoStopAt: nil) {
        case .stop(let reason): reason
        default: nil
        }
    }

    /// Whether the current chunk should be closed and a new one started.
    static func shouldRotateChunk(startedAt: Date, now: Date, chunkDuration: TimeInterval) -> Bool {
        now.timeIntervalSince(startedAt) >= chunkDuration
    }
}
