import SpikeS7Duo
import SwiftUI

private struct S7Layout: Equatable {
    var rect = DuoRect()
    var insets = DuoInsets()
}

/// Live observations only: no model-based fold inference or invented hinge.
struct S7View: View {
    @Environment(LabSession.self) private var session
    @Environment(\.scenePhase) private var phase
    @SceneStorage("S7.counter") private var sceneCounter = 0
    @SceneStorage("S7.identity") private var sceneIdentity = ""
    @State private var stateCounter = 0
    @State private var stateIdentity = UUID().uuidString
    @State private var journal = S7Journal()
    @State private var uiKit = DuoSnapshot()
    @State private var layout = S7Layout()

    var body: some View {
        List {
            Section("Run") {
                Text(
                    "No fixture or external drive needed. Keep this screen open while folding and rotating."
                )
                Button("Start new run") {
                    journal.start()
                    sceneCounter = 0
                    stateCounter = 0
                    record("start run", force: true)
                }
                Button("Increment both counters") {
                    sceneCounter += 1
                    stateCounter += 1
                    record("increment both counters", force: true)
                }
                .accessibilityIdentifier("clovelab.s7.increment")
                Menu("Record checkpoint") {
                    ForEach(
                        ["Cover", "Unfolded", "Half-fold 90°", "Rotated", "Folded back"], id: \.self
                    ) { label in
                        Button(label) { record("checkpoint: \(label)", force: true) }
                    }
                }
                Button("Write S7 report") {
                    record("export", force: true)
                    session.export(journal.log.report())
                }
                .disabled(uiKit.sceneID == "unattached")
                .accessibilityIdentifier("clovelab.s7.writeReport")
                Text("Events: \(journal.log.events.count)")
                if let error = journal.error {
                    Text(error).foregroundStyle(.red)
                }
            }
            Section("State survived") {
                LabeledContent("SceneStorage counter", value: String(sceneCounter))
                LabeledContent("State counter", value: String(stateCounter))
                Text(
                    "Increment once on the cover. Both values should stay at 1 through all postures. A changed State ID shows view recreation; a changed scene ID shows a different scene session."
                )
                .font(.footnote)
                value("Scene session ID", uiKit.sceneID)
                value("SceneStorage ID", sceneIdentity)
                value("State ID", stateIdentity)
            }
            Section("Live geometry (points)") {
                value("Window x,y,w,h", uiKit.window.text)
                value("Scene x,y,w,h", uiKit.scene.text)
                value("UIKit probe x,y,w,h", uiKit.view.text)
                value("SwiftUI viewport x,y,w,h", layout.rect.text)
                value(
                    "Size classes (H / V)",
                    "\(uiKit.horizontalSizeClass) / \(uiKit.verticalSizeClass)")
                value("Window safe area (T,L,B,R)", uiKit.windowSafeArea.text)
                value("Probe safe area (T,L,B,R)", uiKit.viewSafeArea.text)
                value("SwiftUI safe area (T,L,B,R)", layout.insets.text)
                value("Interface orientation", uiKit.orientation)
                value("Scene phase", phaseText)
            }
            Section("Hinge") {
                value("Observation", uiKit.hinge.availability.rawValue)
                value("Status", uiKit.hinge.status ?? "unavailable")
                value(
                    "Angle (radians)",
                    uiKit.hinge.angleRadians.map(String.init(describing:)) ?? "unavailable")
                Text(
                    "Hinge rectangle: \(uiKit.hinge.rectangleDescription). No positional overlay can be drawn from this API."
                )
                .font(.footnote)
                Text(
                    "Status and angle require iOS 27.1 or later. Geometry alone cannot establish the physical hinge position."
                )
                .font(.footnote)
            }
            Section("Latest event") {
                if let event = journal.log.events.last {
                    Text(DuoEvent.timestamp(event.timestamp)).monospacedDigit()
                    Text(event.reason)
                    Text(event.text).font(.caption.monospaced()).textSelection(.enabled)
                }
            }
            Section {
            } footer: {
                DeviceReportFooter()
            }
        }
        .background {
            S7GeometryProbe { sample, reason in
                if uiKit != sample { uiKit = sample }
                record(reason)
            }
        }
        .onGeometryChange(for: S7Layout.self) { proxy in
            let frame = proxy.frame(in: .global)
            let safe = proxy.safeAreaInsets
            return S7Layout(
                rect: DuoRect(
                    x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                insets: DuoInsets(
                    top: safe.top, left: safe.leading, bottom: safe.bottom, right: safe.trailing)
            )
        } action: { value in
            layout = value
            record("SwiftUI geometry")
        }
        .onAppear {
            if sceneIdentity.isEmpty { sceneIdentity = UUID().uuidString }
            record("probe appeared", force: true)
        }
        .onChange(of: phase) { _, _ in record("scene phase", force: true) }
        .navigationTitle("S7 Duo probe")
        .navigationBarTitleDisplayMode(.inline)
        .accessibilityIdentifier("clovelab.spike.S7")
    }

    private var phaseText: String {
        switch phase {
        case .active: "active"
        case .inactive: "inactive"
        case .background: "background"
        @unknown default: "unknown"
        }
    }

    private func value(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(text).font(.footnote.monospaced()).textSelection(.enabled)
        }
    }

    private func record(_ reason: String, force: Bool = false) {
        var snapshot = uiKit
        snapshot.swiftUI = layout.rect
        snapshot.swiftUISafeArea = layout.insets
        snapshot.sceneStorageCounter = sceneCounter
        snapshot.stateCounter = stateCounter
        snapshot.sceneStorageID = sceneIdentity
        snapshot.stateID = stateIdentity
        snapshot.scenePhase = phaseText
        journal.record(snapshot, reason: reason, force: force)
    }
}

#Preview {
    NavigationStack { S7View() }.environment(LabSession())
}
