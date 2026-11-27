import CloveCore
import SwiftUI

/// Reports the device's light or dark style, which a `.preferredColorScheme` override cannot change.
///
/// `RootView` sets the hosting view's color scheme from the theme in effect, so it must not read
/// the color scheme of the tree it overrides. This reader reads and observes the `UIWindowScene`'s
/// `traitCollection.userInterfaceStyle`, which stays the system/device appearance rather than
/// `UIScreen.traitCollection` (detached from live trait updates) or the overridden hosting tree.
struct SystemAppearanceReader: UIViewRepresentable {
    /// The scene's style now, and after each change.
    let onChange: (ThemeAppearance) -> Void

    func makeUIView(context: Context) -> ReporterView {
        ReporterView(onChange: onChange)
    }

    func updateUIView(_ view: ReporterView, context: Context) {
        view.onChange = onChange
        // The report writes the owner's state, which SwiftUI forbids during a view update, so it
        // runs on the next main-actor turn. It catches a change the trait callback missed: with a
        // forced theme in effect the scene can switch style without the view's traits changing.
        Task { @MainActor [weak view] in view?.report() }
    }

    /// An invisible view that watches the window scene's traits rather than its overridden tree.
    final class ReporterView: UIView {
        var onChange: (ThemeAppearance) -> Void

        private var viewRegistration: UITraitChangeRegistration?
        private var sceneRegistration: UITraitChangeRegistration?
        private weak var observedScene: UIWindowScene?

        init(onChange: @escaping (ThemeAppearance) -> Void) {
            self.onChange = onChange
            super.init(frame: .zero)
            isUserInteractionEnabled = false
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("SystemAppearanceReader does not load from a nib")
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            if viewRegistration == nil, window != nil {
                viewRegistration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                    [weak self] (_: UIView, _: UITraitCollection) in
                    self?.report()
                }
            }
            let currentScene = window?.windowScene
            if currentScene !== observedScene {
                if let previous = sceneRegistration, let previousScene = observedScene {
                    previousScene.unregisterForTraitChanges(previous)
                }
                sceneRegistration = nil
                observedScene = currentScene
                if let currentScene {
                    sceneRegistration = currentScene.registerForTraitChanges(
                        [UITraitUserInterfaceStyle.self]
                    ) { [weak self] (_: UIWindowScene, _: UITraitCollection) in
                        self?.report()
                    }
                }
            }
            report()
        }

        /// Reads the window scene's style, never the hosting controller's or window's overridden one.
        func report() {
            guard let style = window?.windowScene?.traitCollection.userInterfaceStyle
            else { return }
            onChange(style == .dark ? .dark : .light)
        }
    }
}
