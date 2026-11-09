import Foundation
import Testing

@testable import LabSupport

/// 2026-11-13T10:15:30Z, the instant the schema examples use.
private let fixedDate = Date(timeIntervalSince1970: 1_794_564_930)

private let fixedDevice = LabDevice(
    modelIdentifier: "iPhone18,2",
    systemName: "iOS",
    systemVersion: "27.2"
)

private let fixedApp = LabApp(
    bundleIdentifier: "com.mimiqdev.clove.lab", version: "0.1.0", build: "1")

private func sampleReport() -> LabReport {
    LabReport(
        spike: "S2",
        createdAt: fixedDate,
        device: fixedDevice,
        app: fixedApp,
        context: ["fileSystem": "exFAT", "volume": "EOS_DIGITAL"],
        measurements: [
            LabMeasurement(
                name: "embedded-preview-extraction",
                value: 128.4,
                unit: "ms",
                tags: ["format": "CR3"]
            ),
            LabMeasurement(name: "report-size", value: 2048, unit: "bytes"),
        ],
        notes: ["Reported from Clove Lab."]
    )
}

private func jsonObject(_ data: Data) throws -> [String: Any] {
    let object = try JSONSerialization.jsonObject(with: data)
    return try #require(object as? [String: Any])
}

private func sortedKeys(of dictionary: [String: Any]) -> [String] {
    dictionary.keys.sorted()
}

@Test func reportRoundTripsThroughJSON() throws {
    let report = sampleReport()
    let decoded = try LabReport(jsonData: report.encoded())
    #expect(decoded == report)
    #expect(try jsonObject(report.encoded())["schemaVersion"] as? Int == 1)
}

@Test func topLevelKeysMatchTheDocumentedSchema() throws {
    let keys = sortedKeys(of: try jsonObject(sampleReport().encoded()))
    #expect(
        keys == [
            "app", "context", "createdAt", "device", "measurements", "notes", "schemaVersion",
            "spike",
        ]
    )
}

@Test func nestedKeysMatchTheDocumentedSchema() throws {
    let object = try jsonObject(sampleReport().encoded())

    let device = try #require(object["device"] as? [String: Any])
    #expect(sortedKeys(of: device) == ["modelIdentifier", "systemName", "systemVersion"])

    let app = try #require(object["app"] as? [String: Any])
    #expect(sortedKeys(of: app) == ["build", "bundleIdentifier", "version"])

    let measurements = try #require(object["measurements"] as? [[String: Any]])
    #expect(measurements.count == 2)
    #expect(sortedKeys(of: try #require(measurements.first)) == ["name", "tags", "unit", "value"])
}

@Test func datesEncodeAsISO8601UTC() throws {
    let object = try jsonObject(sampleReport().encoded())
    #expect(object["createdAt"] as? String == "2026-11-13T10:15:30Z")
}

@Test func encodingIsStableWithSortedKeys() throws {
    let report = sampleReport()
    #expect(try report.encoded() == report.encoded())

    var first = report
    first.context = ["b": "2", "a": "1", "c": "3"]
    var second = report
    second.context = ["c": "3", "a": "1", "b": "2"]
    #expect(try first.encoded() == second.encoded())

    let text = String(decoding: try report.encoded(), as: UTF8.self)
    let topLevelKeys = text.split(separator: "\n")
        .filter { $0.hasPrefix("  \"") && $0.contains("\" :") }
        .map { line in
            line.dropFirst(3).prefix { $0 != "\"" }
        }
        .map(String.init)
    #expect(topLevelKeys == topLevelKeys.sorted())
    #expect(topLevelKeys.count == 8)
    #expect(text.hasSuffix("}\n"))
}

@Test func encodingKeepsEmptyCollections() throws {
    let report = LabReport(
        spike: "S0",
        createdAt: fixedDate,
        device: fixedDevice,
        app: fixedApp
    )
    let object = try jsonObject(report.encoded())
    #expect(try #require(object["context"] as? [String: Any]).isEmpty)
    #expect(try #require(object["measurements"] as? [Any]).isEmpty)
    #expect(try #require(object["notes"] as? [Any]).isEmpty)
}

@Test func currentDeviceIsFilledIn() {
    let report = LabReport(spike: "S0", createdAt: fixedDate)
    #expect(!report.device.modelIdentifier.isEmpty)
    #expect(!report.device.systemName.isEmpty)
    #expect(!report.device.systemVersion.isEmpty)
    #expect(report.schemaVersion == LabReport.currentSchemaVersion)
}
