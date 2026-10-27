import Foundation
import XCTest
@testable import MacStats

final class TemperatureTests: XCTestCase {
    func testPrefersCPUTemperatureAndRejectsInvalidValues() {
        let reading = PowermetricsReader.parseTemperature(from:
            "GPU die temperature: 48.5 C\nCPU die temperature: 62.25 C\n")
        XCTAssertEqual(reading?.celsius, 62.25)
        XCTAssertEqual(reading?.sensorName, "CPU die temperature")
        XCTAssertNil(PowermetricsReader.parseTemperature(from: "CPU temperature: 150 C"))
    }

    func testCacheFreshnessAndCollectorFailure() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("temperature.txt")
        XCTAssertNil(PowermetricsReader.cachedTemperature(from: url))
        try "CPU die temperature: 55.5 C".write(to: url, atomically: true, encoding: .utf8)
        let modified = try XCTUnwrap(url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate)
        let fresh = try XCTUnwrap(PowermetricsReader.cachedTemperature(from: url, now: modified.addingTimeInterval(10)))
        XCTAssertEqual(try fresh.get().celsius, 55.5)
        XCTAssertNil(PowermetricsReader.cachedTemperature(from: url, now: modified.addingTimeInterval(36)))
        XCTAssertNil(PowermetricsReader.cachedTemperature(from: url, now: modified.addingTimeInterval(-1)))
        try "powermetrics failed".write(to: url, atomically: true, encoding: .utf8)
        let failed = try XCTUnwrap(PowermetricsReader.cachedTemperature(from: url, now: Date().addingTimeInterval(1)))
        XCTAssertThrowsError(try failed.get())
    }
}
