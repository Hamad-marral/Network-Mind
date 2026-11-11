import XCTest
@testable import NetworkMind

final class EventModeGuardsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_750_000_000)
    private let plenty: Int64 = 50 * 1024 * 1024 * 1024

    private func conditions(battery: Float = 0.8, charging: Bool = false, free: Int64? = nil) -> DeviceConditions {
        DeviceConditions(batteryLevel: battery, isCharging: charging, freeBytes: free ?? plenty)
    }

    func testHealthyDeviceIsOK() {
        XCTAssertEqual(EventModeGuards.evaluate(conditions: conditions(), now: now, autoStopAt: now.addingTimeInterval(60)), .ok)
    }

    func testAutoStopTakesPriority() {
        let decision = EventModeGuards.evaluate(conditions: conditions(battery: 0.05), now: now, autoStopAt: now)
        XCTAssertEqual(decision, .stop(.autoStop))
    }

    func testLowBatteryStopsUnlessCharging() {
        XCTAssertEqual(EventModeGuards.evaluate(conditions: conditions(battery: 0.09), now: now, autoStopAt: nil), .stop(.lowBattery))
        XCTAssertEqual(EventModeGuards.evaluate(conditions: conditions(battery: 0.09, charging: true), now: now, autoStopAt: nil), .ok)
    }

    func testUnknownBatteryIsIgnored() {
        XCTAssertEqual(EventModeGuards.evaluate(conditions: conditions(battery: -1), now: now, autoStopAt: nil), .ok)
    }

    func testBatteryWarningBand() {
        guard case .warn(let message) = EventModeGuards.evaluate(conditions: conditions(battery: 0.15), now: now, autoStopAt: nil) else {
            return XCTFail("Expected a warning")
        }
        XCTAssertTrue(message.contains("15%"))
    }

    func testStorageStopAndWarning() {
        XCTAssertEqual(EventModeGuards.evaluate(conditions: conditions(free: 100 * 1024 * 1024), now: now, autoStopAt: nil), .stop(.lowStorage))
        guard case .warn = EventModeGuards.evaluate(conditions: conditions(free: 500 * 1024 * 1024), now: now, autoStopAt: nil) else {
            return XCTFail("Expected a storage warning")
        }
        XCTAssertEqual(EventModeGuards.evaluate(conditions: DeviceConditions(batteryLevel: 0.5, isCharging: false, freeBytes: nil), now: now, autoStopAt: nil), .ok)
    }

    func testCanStart() {
        XCTAssertNil(EventModeGuards.canStart(conditions: conditions()))
        XCTAssertEqual(EventModeGuards.canStart(conditions: conditions(battery: 0.05)), .lowBattery)
        XCTAssertEqual(EventModeGuards.canStart(conditions: conditions(free: 1024)), .lowStorage)
    }

    func testChunkRotation() {
        XCTAssertFalse(EventModeGuards.shouldRotateChunk(startedAt: now, now: now.addingTimeInterval(299), chunkDuration: 300))
        XCTAssertTrue(EventModeGuards.shouldRotateChunk(startedAt: now, now: now.addingTimeInterval(300), chunkDuration: 300))
    }

    func testStopReasonMessagesAreUserFacing() {
        for reason in [EventModeStopReason.user, .autoStop, .lowBattery, .lowStorage, .crashRecovery, .error] {
            XCTAssertFalse(reason.message.isEmpty)
        }
    }

    func testFileHasAudioRejectsEmptyAndMissingFiles() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).m4a")
        XCTAssertFalse(EventModeManager.fileHasAudio(url))
        try Data(count: 10).write(to: url)
        XCTAssertFalse(EventModeManager.fileHasAudio(url))
        try Data(count: 10_000).write(to: url)
        XCTAssertTrue(EventModeManager.fileHasAudio(url))
        try? FileManager.default.removeItem(at: url)
    }
}
