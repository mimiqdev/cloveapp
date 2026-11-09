import SpikeS7Duo
import SwiftUI
import UIKit

/// Attached to the full probe viewport, not to a list cell. The window and
/// scene are read from this view's hierarchy, never UIApplication's first scene.
struct S7GeometryProbe: UIViewRepresentable {
    var onSample: @MainActor (DuoSnapshot, String) -> Void

    func makeUIView(context: Context) -> S7ProbeView {
        let view = S7ProbeView()
        view.onSample = onSample
        view.installHingeObservation()
        return view
    }

    func updateUIView(_ uiView: S7ProbeView, context: Context) {
        uiView.onSample = onSample
        uiView.sample(reason: "SwiftUI update")
    }
}

@MainActor
final class S7ProbeView: UIView {
    var onSample: (@MainActor (DuoSnapshot, String) -> Void)?
    private var hinge = DuoHinge(availability: .requiresIOS27_1)

    init() {
        super.init(frame: .zero)
        isUserInteractionEnabled = false
        registerForTraitChanges([UITraitHorizontalSizeClass.self, UITraitVerticalSizeClass.self]) {
            (view: S7ProbeView, _: UITraitCollection) in
            view.sample(reason: "size classes")
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func installHingeObservation() {
        if #available(iOS 27.1, *) {
            hinge = DuoHinge(availability: .awaitingUpdate)
            addInteraction(
                UIHingeInteraction { [weak self] _, update in
                    guard let self else { return }
                    if let value = update.hinge {
                        let status: String
                        switch value.status {
                        case .unknown: status = "unknown"
                        case .closed: status = "closed"
                        case .partiallyOpen: status = "partiallyOpen"
                        case .fullyOpen: status = "fullyOpen"
                        @unknown default: status = "unrecognized(\(value.status.rawValue))"
                        }
                        self.hinge = DuoHinge(
                            availability: .reported, status: status,
                            angleRadians: Double(value.angle))
                    } else {
                        self.hinge = DuoHinge(availability: .noHingeInHierarchy)
                    }
                    self.sample(reason: "hinge callback")
                })
        }
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        sample(reason: "window attachment")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        sample(reason: "layout")
    }

    override func safeAreaInsetsDidChange() {
        super.safeAreaInsetsDidChange()
        sample(reason: "safe area")
    }

    func sample(reason: String) {
        guard let window, let scene = window.windowScene else { return }
        var snapshot = DuoSnapshot()
        snapshot.window = Self.rect(window.bounds)
        snapshot.view = Self.rect(bounds)
        let geometry = scene.effectiveGeometry
        if #available(iOS 26.0, *) {
            snapshot.scene = Self.rect(geometry.coordinateSpace.bounds)
        } else {
            snapshot.scene = Self.rect(scene.coordinateSpace.bounds)
        }
        snapshot.windowSafeArea = Self.insets(window.safeAreaInsets)
        snapshot.viewSafeArea = Self.insets(safeAreaInsets)
        snapshot.horizontalSizeClass = Self.sizeClass(traitCollection.horizontalSizeClass)
        snapshot.verticalSizeClass = Self.sizeClass(traitCollection.verticalSizeClass)
        snapshot.orientation = Self.orientation(geometry.interfaceOrientation)
        snapshot.sceneID = scene.session.persistentIdentifier
        snapshot.hinge = hinge
        // UIKit may be laying out SwiftUI. Deliver the immutable sample after
        // that transaction to avoid mutating SwiftUI state during view updates.
        let sample = snapshot
        DispatchQueue.main.async { [weak self] in self?.onSample?(sample, reason) }
    }

    static func rect(_ rect: CGRect) -> DuoRect {
        DuoRect(x: rect.minX, y: rect.minY, width: rect.width, height: rect.height)
    }

    static func insets(_ insets: UIEdgeInsets) -> DuoInsets {
        DuoInsets(top: insets.top, left: insets.left, bottom: insets.bottom, right: insets.right)
    }

    private static func sizeClass(_ value: UIUserInterfaceSizeClass) -> String {
        switch value {
        case .compact: "compact"
        case .regular: "regular"
        case .unspecified: "unspecified"
        @unknown default: "unrecognized(\(value.rawValue))"
        }
    }

    private static func orientation(_ value: UIInterfaceOrientation) -> String {
        switch value {
        case .portrait: "portrait"
        case .portraitUpsideDown: "portraitUpsideDown"
        case .landscapeLeft: "landscapeLeft"
        case .landscapeRight: "landscapeRight"
        case .unknown: "unknown"
        @unknown default: "unrecognized(\(value.rawValue))"
        }
    }
}
