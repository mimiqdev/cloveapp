import Foundation

/// The device a Clove Lab report was produced on.
public struct LabDevice: Codable, Sendable, Hashable {
    /// Hardware model identifier, for example `iPhone18,2`.
    public var modelIdentifier: String
    /// Operating system name, for example `iOS`.
    public var systemName: String
    /// Operating system version, for example `18.0`.
    public var systemVersion: String

    public init(modelIdentifier: String, systemName: String, systemVersion: String) {
        self.modelIdentifier = modelIdentifier
        self.systemName = systemName
        self.systemVersion = systemVersion
    }

    /// The device and system running this process.
    ///
    /// On the simulator the model identifier comes from
    /// `SIMULATOR_MODEL_IDENTIFIER`, so reports match the simulated device
    /// rather than the Mac.
    public static func current(
        processInfo: ProcessInfo = .processInfo,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> LabDevice {
        let version = processInfo.operatingSystemVersion
        var versionString = "\(version.majorVersion).\(version.minorVersion)"
        if version.patchVersion > 0 {
            versionString += ".\(version.patchVersion)"
        }
        return LabDevice(
            modelIdentifier: hardwareIdentifier(environment: environment),
            systemName: systemName,
            systemVersion: versionString
        )
    }

    #if os(macOS)
        private static let systemName = "macOS"
    #else
        private static let systemName = "iOS"
    #endif

    private static func hardwareIdentifier(environment: [String: String]) -> String {
        if let simulated = environment["SIMULATOR_MODEL_IDENTIFIER"], !simulated.isEmpty {
            return simulated
        }
        #if os(macOS)
            return sysctlValue("hw.model") ?? "unknown"
        #else
            return sysctlValue("hw.machine") ?? "unknown"
        #endif
    }

    private static func sysctlValue(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else {
            return nil
        }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else {
            return nil
        }
        return String(decoding: buffer.prefix { $0 != 0 }, as: UTF8.self)
    }
}

/// The app a Clove Lab report was produced by.
public struct LabApp: Codable, Sendable, Hashable {
    /// Bundle identifier, for example `com.mimiqdev.clove.lab`.
    public var bundleIdentifier: String
    /// Marketing version, `CFBundleShortVersionString`.
    public var version: String
    /// Build number, `CFBundleVersion`.
    public var build: String

    public init(bundleIdentifier: String, version: String, build: String) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.build = build
    }

    /// The app running this process.
    public static func current(bundle: Bundle = .main) -> LabApp {
        func infoString(_ key: String) -> String {
            bundle.object(forInfoDictionaryKey: key) as? String ?? ""
        }
        return LabApp(
            bundleIdentifier: bundle.bundleIdentifier ?? "",
            version: infoString("CFBundleShortVersionString"),
            build: infoString("CFBundleVersion")
        )
    }
}

/// One named number a probe measured, with its unit and free-form tags.
public struct LabMeasurement: Codable, Sendable, Hashable {
    /// What was measured, for example `embedded-preview-extraction`.
    public var name: String
    /// The measured value in `unit`, for example `128.4`.
    public var value: Double
    /// Unit of `value`, for example `ms` or `bytes`.
    public var unit: String
    /// Extra labels, for example `["format": "CR3"]`.
    public var tags: [String: String]

    public init(name: String, value: Double, unit: String, tags: [String: String] = [:]) {
        self.name = name
        self.value = value
        self.unit = unit
        self.tags = tags
    }
}

/// The JSON report a probe writes on device, analyzed back on the Mac.
///
/// The key names are part of the schema in `docs/spikes/README.md`; change both
/// together. Dates are ISO 8601 in UTC.
public struct LabReport: Codable, Sendable, Equatable {
    /// Schema version written into every report. Bump it when a field changes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Probe identifier, for example `S2`.
    public var spike: String
    /// When the report was produced.
    public var createdAt: Date
    public var device: LabDevice
    public var app: LabApp
    /// Free-form context, for example the volume's file system.
    public var context: [String: String]
    public var measurements: [LabMeasurement]
    public var notes: [String]

    public init(
        spike: String,
        createdAt: Date = Date(),
        device: LabDevice = .current(),
        app: LabApp = .current(),
        context: [String: String] = [:],
        measurements: [LabMeasurement] = [],
        notes: [String] = []
    ) {
        self.schemaVersion = LabReport.currentSchemaVersion
        self.spike = spike
        self.createdAt = createdAt
        self.device = device
        self.app = app
        self.context = context
        self.measurements = measurements
        self.notes = notes
    }
}

extension LabReport {
    /// Encoder for reports: pretty printed, sorted keys, ISO 8601 UTC dates.
    public static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    /// Decoder matching ``makeEncoder()``.
    public static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    /// The report as JSON, ending with a newline.
    public func encoded() throws -> Data {
        var data = try LabReport.makeEncoder().encode(self)
        data.append(Data("\n".utf8))
        return data
    }

    public init(jsonData: Data) throws {
        self = try LabReport.makeDecoder().decode(LabReport.self, from: jsonData)
    }

    /// Writes the report as JSON to `url`, atomically.
    public func write(to url: URL) throws {
        try encoded().write(to: url, options: .atomic)
    }
}
