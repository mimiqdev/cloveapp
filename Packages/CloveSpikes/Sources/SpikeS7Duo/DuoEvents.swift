import Foundation
import SpikeSupport

/// Point values in the coordinate space named by the field (never pixels).
public struct DuoRect: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    public init(x: Double = 0, y: Double = 0, width: Double = 0, height: Double = 0) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public var text: String { "\(x),\(y),\(width),\(height)" }
}

public struct DuoInsets: Codable, Sendable, Equatable {
    public var top: Double
    public var left: Double
    public var bottom: Double
    public var right: Double

    public init(top: Double = 0, left: Double = 0, bottom: Double = 0, right: Double = 0) {
        self.top = top
        self.left = left
        self.bottom = bottom
        self.right = right
    }

    public var text: String { "\(top),\(left),\(bottom),\(right)" }
}

/// Absence of an API, absence of a hinge, and waiting for the initial callback
/// are different observations. None implies a closed device.
public struct DuoHinge: Codable, Sendable, Equatable {
    public enum Availability: String, Codable, Sendable {
        case requiresIOS27_1
        case awaitingUpdate
        case noHingeInHierarchy
        case reported
    }

    public var availability: Availability
    public var status: String?
    public var angleRadians: Double?

    public init(availability: Availability, status: String? = nil, angleRadians: Double? = nil) {
        self.availability = availability
        self.status = status
        self.angleRadians = angleRadians
    }

    // The 27.2 public APIs expose no position/rectangle. Do not synthesize one
    // from the midpoint, angle, or a device model.
    public var rectangleDescription: String { "not exposed by SDK 27.2" }
}

/// One complete observation, independent of UIKit so continuity and report
/// semantics can be tested on macOS and reused by P3/P4.
public struct DuoSnapshot: Codable, Sendable, Equatable {
    public var window = DuoRect()
    public var scene = DuoRect()
    public var view = DuoRect()
    public var swiftUI = DuoRect()
    public var windowSafeArea = DuoInsets()
    public var viewSafeArea = DuoInsets()
    public var swiftUISafeArea = DuoInsets()
    public var horizontalSizeClass = "unspecified"
    public var verticalSizeClass = "unspecified"
    public var orientation = "unknown"
    public var sceneID = "unattached"
    public var scenePhase = "unknown"
    public var sceneStorageID = ""
    public var stateID = ""
    public var sceneStorageCounter = 0
    public var stateCounter = 0
    public var hinge = DuoHinge(availability: .requiresIOS27_1)

    public init() {}

    public var tags: [String: String] {
        [
            "window.xywh.pt": window.text,
            "scene.xywh.pt": scene.text,
            "view.xywh.pt": view.text,
            "swiftUI.xywh.pt": swiftUI.text,
            "window.safeArea.tlbr.pt": windowSafeArea.text,
            "view.safeArea.tlbr.pt": viewSafeArea.text,
            "swiftUI.safeArea.tlbr.pt": swiftUISafeArea.text,
            "horizontalSizeClass": horizontalSizeClass,
            "verticalSizeClass": verticalSizeClass,
            "orientation": orientation,
            "sceneID": sceneID,
            "scenePhase": scenePhase,
            "sceneStorageID": sceneStorageID,
            "stateID": stateID,
            "sceneStorageCounter": String(sceneStorageCounter),
            "stateCounter": String(stateCounter),
            "hinge.availability": hinge.availability.rawValue,
            "hinge.status": hinge.status ?? "unavailable",
            "hinge.angle.radians": hinge.angleRadians.map(String.init(describing:))
                ?? "unavailable",
            "hinge.rectangle": hinge.rectangleDescription,
        ]
    }
}

public struct DuoEvent: Codable, Sendable, Equatable {
    public let timestamp: Date
    public let reason: String
    public let snapshot: DuoSnapshot

    public var text: String {
        let fields = snapshot.tags.sorted { $0.key < $1.key }
            .map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
        return "\(Self.timestamp(timestamp)) [\(reason)] \(fields)"
    }

    public static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: date)
    }
}

/// A journal survives probe/view recreation. Sensor samples are deduplicated;
/// explicit operator checkpoints and lifecycle events can be forced.
public struct DuoLog: Codable, Sendable, Equatable {
    public let runID: String
    public private(set) var events: [DuoEvent] = []

    public init(runID: String = UUID().uuidString) {
        self.runID = runID
    }

    @discardableResult
    public mutating func record(
        _ snapshot: DuoSnapshot, reason: String, at date: Date = Date(), force: Bool = false
    ) -> Bool {
        guard force || events.last?.snapshot != snapshot else { return false }
        events.append(DuoEvent(timestamp: date, reason: reason, snapshot: snapshot))
        return true
    }

    public func report(
        createdAt: Date = Date(), device: LabDevice = .current(), app: LabApp = .current()
    ) -> LabReport {
        LabReport(
            spike: "S7", createdAt: createdAt, device: device, app: app,
            context: [
                "runID": runID,
                "sdk": "27.2",
                "coordinateUnits": "points",
                "rectangleOrder": "x,y,width,height",
                "insetOrder": "top,left,bottom,right",
                "hingeRectangle": "not exposed by public SDK 27.2 APIs",
            ],
            measurements: events.enumerated().map { index, event in
                var tags = event.snapshot.tags
                tags["timestamp"] = DuoEvent.timestamp(event.timestamp)
                tags["reason"] = event.reason
                return LabMeasurement(
                    name: "duo-event", value: Double(index + 1), unit: "count", tags: tags)
            },
            notes: [
                "State IDs identify view recreation; sceneID identifies the UIKit session, not an object instance.",
                "SceneStorage is system-managed restoration, not durable storage for production writes.",
                "No hinge rectangle is reported; physical alignment and Duo continuity remain device checks.",
            ]
        )
    }
}
