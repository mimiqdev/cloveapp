import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

func fail(_ message: String, code: Int32 = 1) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

func command(_ arguments: [String], executable: String = "/usr/bin/xcrun") -> Data {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = FileHandle.standardError
    do { try process.run() } catch { fail("Cannot run \(executable): \(error)") }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        fail("\(executable) \(arguments.joined(separator: " ")) failed")
    }
    return data
}

struct DeviceList: Decodable {
    struct Device: Decodable {
        let udid: String
        let name: String
        let state: String
        let deviceTypeIdentifier: String?
    }
    let devices: [String: [Device]]
}

struct OwnedDevice {
    let id: UUID
    let name: String

    init(id: String, name: String) {
        guard let uuid = UUID(uuidString: id), name.hasPrefix("Clove ") else {
            fail("Supply an owned simulator UUID and its exact 'Clove ...' name.", code: 64)
        }
        let data = command(["simctl", "list", "devices", "--json"])
        guard let list = try? JSONDecoder().decode(DeviceList.self, from: data) else {
            fail("Cannot read the simulator inventory")
        }
        let devices = list.devices.values.flatMap { $0 }
        guard
            let device = devices.first(where: { $0.udid.caseInsensitiveCompare(id) == .orderedSame }
            ),
            device.name == name, device.state == "Booted",
            device.deviceTypeIdentifier == "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"
        else { fail("The supplied ID/name is not a booted owned iPhone Duo: \(name) (\(id))") }
        guard devices.filter({ $0.name == name }).count == 1 else {
            fail("Device Hub selection would be ambiguous: multiple devices are named '\(name)'.")
        }
        self.id = uuid
        self.name = name
    }
}

enum Pose: String {
    case open
    case partiallyOpen = "partially-open"
    case closed

    var label: String {
        switch self {
        case .open: "Open"
        case .partiallyOpen: "Partially Open"
        case .closed: "Closed"
        }
    }
}

struct DisplayInventory: Decodable {
    struct Empty: Decodable {}
    struct Display: Decodable {
        let displayId: Int
        let active: Bool
        let nativeSize: [Double]
        let type: [String: Empty]
    }
    struct Result: Decodable { let displays: [Display] }
    let result: Result
}

func confirmDisplay(_ device: OwnedDevice, pose: Pose) {
    let deadline = Date().addingTimeInterval(10)
    var observed = "no display inventory"
    repeat {
        let data = command([
            "devicectl", "device", "info", "displays", "--device", device.id.uuidString,
            "--json-output", "-", "--quiet", "--timeout", "5",
        ])
        guard let inventory = try? JSONDecoder().decode(DisplayInventory.self, from: data) else {
            fail("Cannot read the owned Duo's public display inventory.")
        }
        let displays = inventory.result.displays.filter {
            $0.type["integrated"] != nil && $0.nativeSize.count == 2
        }.sorted { $0.nativeSize.reduce(1, *) < $1.nativeSize.reduce(1, *) }
        guard displays.count == 2 else { fail("Expected the owned Duo's two integrated displays.") }
        let target = pose == .closed ? displays[0] : displays[1]
        observed = displays.map { "display \($0.displayId) active=\($0.active)" }.joined(
            separator: ", ")
        if target.active {
            print(
                "Confirmed \(pose == .closed ? "cover" : "inner") display \(target.displayId) active at native size \(target.nativeSize)."
            )
            return
        }
        yieldToGUI()
    } while Date() < deadline
    fail(
        "Device Hub accepted \(pose.label), but the owned Duo did not activate the expected real display within 10 seconds. Observed: \(observed)."
    )
}

func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
    var result: CFTypeRef?
    let error = AXUIElementCopyAttributeValue(element, name as CFString, &result)
    if error == .apiDisabled {
        fail(
            "Accessibility access was revoked. Run scripts/duo-pose.sh --request-access.", code: 77)
    }
    return error == .success ? result : nil
}

func text(_ element: AXUIElement, _ name: String) -> String {
    attribute(element, name) as? String ?? ""
}

func labels(_ element: AXUIElement) -> [String] {
    [
        kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXIdentifierAttribute,
        kAXHelpAttribute,
    ]
    .map { text(element, $0) }.filter { !$0.isEmpty }
}

func walk(
    _ root: AXUIElement, limit: Int = 800,
    until deadline: Date = Date().addingTimeInterval(12)
) -> [AXUIElement] {
    var queue = [root]
    var index = 0
    while index < queue.count && index < limit && Date() < deadline {
        let children = attribute(queue[index], kAXChildrenAttribute) as? [AXUIElement] ?? []
        queue.append(contentsOf: children)
        index += 1
    }
    return Array(queue.prefix(index))
}

func windowShows(_ window: AXUIElement, device: OwnedDevice) -> Bool {
    let title = text(window, kAXTitleAttribute)
    if title == device.name { return true }
    let parts = title.components(separatedBy: " – ")
    return parts.last?.hasPrefix("iOS ") == true
        && parts.dropLast().joined(separator: " – ") == device.name
}

func select(_ element: AXUIElement) -> Bool {
    var candidate = element
    var row: AXUIElement?
    for _ in 0..<10 {
        let role = text(candidate, kAXRoleAttribute)
        if role == kAXRowRole { row = candidate }
        var settable = DarwinBoolean(false)
        if let row, [kAXOutlineRole, kAXTableRole].contains(role),
            AXUIElementIsAttributeSettable(
                candidate, kAXSelectedRowsAttribute as CFString, &settable) == .success,
            settable.boolValue,
            AXUIElementSetAttributeValue(
                candidate, kAXSelectedRowsAttribute as CFString, [row] as CFArray) == .success
        {
            return true
        }
        if AXUIElementIsAttributeSettable(candidate, kAXSelectedAttribute as CFString, &settable)
            == .success,
            settable.boolValue,
            AXUIElementSetAttributeValue(
                candidate, kAXSelectedAttribute as CFString, kCFBooleanTrue) == .success
        {
            return true
        }
        var actionNames: CFArray?
        AXUIElementCopyActionNames(candidate, &actionNames)
        if (actionNames as? [String] ?? []).contains(kAXPressAction),
            AXUIElementPerformAction(candidate, kAXPressAction as CFString) == .success
        {
            return true
        }
        guard let parent = attribute(candidate, kAXParentAttribute),
            CFGetTypeID(parent) == AXUIElementGetTypeID()
        else { return false }
        candidate = unsafeDowncast(parent, to: AXUIElement.self)
        if text(candidate, kAXRoleAttribute) == kAXWindowRole { return false }
    }
    return false
}

func yieldToGUI() { RunLoop.current.run(until: Date().addingTimeInterval(0.2)) }

func deviceHub() -> AXUIElement {
    let path = String(decoding: command(["-p"], executable: "/usr/bin/xcode-select"), as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    let app = URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent(
        "Applications/DeviceHub.app")
    let executable = app.appendingPathComponent("Contents/MacOS/DeviceHub").path
    guard FileManager.default.isExecutableFile(atPath: executable) else {
        fail("Cannot locate Device Hub in selected Xcode.")
    }
    func processID() -> pid_t? {
        // The bundle launcher is DevicesTrampoline; target the actual Device Hub GUI process.
        let processes = String(
            decoding: command(["-wwaxo", "uid=,pid=,comm="], executable: "/bin/ps"), as: UTF8.self)
        for line in processes.split(separator: "\n") {
            let fields = line.trimmingCharacters(in: .whitespaces).split(
                maxSplits: 2, whereSeparator: \.isWhitespace)
            if fields.count == 3, UInt32(fields[0]) == getuid(), String(fields[2]) == executable {
                return pid_t(fields[1])
            }
        }
        return nil
    }
    if CommandLine.arguments.contains("--inspect") { print("Device Hub executable: \(executable)") }
    if processID() == nil {
        guard NSWorkspace.shared.open(app) else { fail("Cannot launch Device Hub at \(app.path)") }
    }
    let deadline = Date().addingTimeInterval(15)
    repeat {
        if let pid = processID() {
            let element = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(element, 2)
            if text(element, kAXRoleAttribute) == kAXApplicationRole {
                AXUIElementSetAttributeValue(
                    element, kAXFrontmostAttribute as CFString, kCFBooleanTrue)
                return element
            }
        }
        yieldToGUI()
    } while Date() < deadline
    fail(
        "Device Hub did not become Accessibility-ready within 15 seconds in the logged-in GUI session. Check that it has finished launching; inspect with --inspect."
    )
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let session = CGSessionCopyCurrentDictionary() as? [String: Any],
    (session["kCGSSessionUserIDKey"] as? NSNumber)?.uint32Value == getuid(),
    session["kCGSSessionOnConsoleKey"] as? Bool == true,
    session["kCGSessionLoginDoneKey"] as? Bool == true
else {
    fail(
        "A macOS GUI session must remain logged in as \(NSUserName()) to operate Device Hub.",
        code: 78)
}
if session["CGSSessionScreenIsLocked"] as? Bool == true {
    fail(
        "The GUI session is logged in but locked. Unlock the Mini through Screen Sharing and keep it unlocked for Device Hub AX tests; no manual pose click is required.",
        code: 78)
}
let prompts = arguments.contains("--request-access")
if prompts || arguments.contains("--check-access") {
    guard arguments.count == 1 else {
        fail("Use the access-check/request mode separately from device pose actions.", code: 64)
    }
}
let options = ["AXTrustedCheckOptionPrompt": prompts] as CFDictionary
let trusted = AXIsProcessTrustedWithOptions(options)
if !trusted {
    if prompts,
        let settings = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    {
        NSWorkspace.shared.open(settings)
    }
    fail(
        "Accessibility is not granted to this launch context. Run scripts/duo-pose.sh --request-access and enable the responsible entry in Privacy & Security → Accessibility. This helper uses direct AX APIs, not System Events/Apple Events.",
        code: 77)
}
if arguments.contains("--check-access") || prompts {
    print("Accessibility granted; GUI session is logged in and unlocked for \(NSUserName()).")
    exit(0)
}
func option(_ name: String) -> String? {
    guard let index = arguments.firstIndex(of: name), arguments.indices.contains(index + 1) else {
        return nil
    }
    return arguments[index + 1]
}
guard let id = option("--udid"), let name = option("--name") else {
    fail(
        "Usage: duo-devicehub --udid UUID --name 'Clove ...' --pose open|partially-open|closed [--inspect]",
        code: 64)
}
if arguments.contains("--inspect") {
    _ = OwnedDevice(id: id, name: name)
    let app = deviceHub()
    var pid: pid_t = 0
    AXUIElementGetPid(app, &pid)
    var names: CFArray?
    let status = AXUIElementCopyAttributeNames(app, &names)
    print(
        "Device Hub PID: \(pid); AX attribute status: \(status.rawValue); attributes: \(names as? [String] ?? [])"
    )
    for key in [kAXMainWindowAttribute, kAXFocusedWindowAttribute] {
        if let value = attribute(app, key), CFGetTypeID(value) == AXUIElementGetTypeID() {
            let window = unsafeDowncast(value, to: AXUIElement.self)
            print(
                "\(key): role=\(text(window, kAXRoleAttribute)), labels=\(labels(window)), equalsApp=\(CFEqual(window, app))"
            )
        }
    }
    for window in attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? [] {
        print(
            "Window entry equals application: \(CFEqual(window, app)); \(CFCopyDescription(window) as String? ?? "nil")"
        )
        for element in walk(window) {
            print("\(text(element, kAXRoleAttribute)) \(labels(element))")
            if text(element, kAXRoleAttribute) == kAXOutlineRole {
                let rows = attribute(element, kAXRowsAttribute) as? [AXUIElement] ?? []
                print("Outline rows: \(rows.count)")
            }
        }
    }
    exit(0)
}
guard let value = option("--pose"), let pose = Pose(rawValue: value) else {
    fail("A supported --pose is required.", code: 64)
}
let device = OwnedDevice(id: id, name: name)
let app = deviceHub()
let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
if !windows.contains(where: { windowShows($0, device: device) }) {
    let identifier = "TableRow.Device.\(device.id.uuidString)"
    let rowDeadline = Date().addingTimeInterval(10)
    var row: AXUIElement?
    repeat {
        let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
        row = windows.lazy.flatMap { walk($0, until: rowDeadline) }.first(where: {
            text($0, kAXIdentifierAttribute) == identifier
                && text($0, kAXRoleAttribute) == kAXStaticTextRole
        })
        if row != nil { break }
        yieldToGUI()
    } while Date() < rowDeadline
    guard let row else {
        fail(
            "Device Hub did not expose the owned simulator's UUID sidebar row: \(device.name) (\(device.id.uuidString)). Inspect with --inspect."
        )
    }
    guard select(row) else {
        fail(
            "The owned simulator's UUID row exists but is not selectable through AX: \(device.name). Inspect with --inspect."
        )
    }
}
let selectionDeadline = Date().addingTimeInterval(10)
while !(attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []).contains(where: {
    windowShows($0, device: device)
}) {
    guard Date() < selectionDeadline else {
        fail(
            "Device Hub did not display the owned simulator '\(device.name)' after selecting its UUID row."
        )
    }
    yieldToGUI()
}
let deadline = Date().addingTimeInterval(10)
repeat {
    let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] ?? []
    for window in windows {
        guard windowShows(window, device: device) else { continue }
        guard AXUIElementPerformAction(window, kAXRaiseAction as CFString) == .success else {
            fail("Cannot raise the owned simulator's Device Hub window: \(device.name).")
        }
        let elements = walk(window, until: deadline)
        let buttons = elements.filter {
            [kAXButtonRole, kAXRadioButtonRole].contains(text($0, kAXRoleAttribute))
                && attribute($0, kAXEnabledAttribute) as? Bool == true
                && labels($0).contains(where: {
                    $0.caseInsensitiveCompare(pose.label) == .orderedSame
                })
        }
        if buttons.count == 1 {
            guard AXUIElementPerformAction(buttons[0], kAXPressAction as CFString) == .success
            else {
                fail("Device Hub rejected the \(pose.label) pose action for '\(device.name)'.")
            }
            print(
                "Set \(pose.label) on \(device.name) (\(device.id.uuidString)) using its semantic AX control."
            )
            confirmDisplay(device, pose: pose)
            exit(0)
        }
    }
    yieldToGUI()
} while Date() < deadline
fail(
    "Cannot find a unique \(pose.label) pose control in the owned simulator's Device Hub window. No other device was changed; inspect with --inspect."
)
