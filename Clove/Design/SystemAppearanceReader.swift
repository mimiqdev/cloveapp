import CloveCore
import SwiftUI

/// Reports the device's light or dark style, which a `.preferredColorScheme` override cannot change
/// (`design/handoff/tokens/tokens.md`).
///
/// `RootView` sets the window's color scheme from the theme in effect, so it must not read the
/// color scheme of the tree it overrides. This reader takes the style from the window scene's
/// screen, whose traits stay the device's own, and reports it again whenever the viewer's traits
/// change.
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
        // forced theme in effect the screen can switch style without the view's traits changing.
        Task { @MainActor [weak view] in view?.report() }
    }

    /// An invisible view that watches the scene rather than its own traits.
    final class ReporterView: UIView {
        var onChange: (ThemeAppearance) -> Void

        private var registration: UITraitChangeRegistration?

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
            guard registration == nil, window != nil else { return }
            registration = registerForTraitChanges([UITraitUserInterfaceStyle.self]) {
                [weak self] (_: UIView, _: UITraitCollection) in
                self?.report()
            }
            report()
        }

        /// Reads the screen's style, never the scene's or the window's overridden one.
        ///
        /// The scene and the window take the app's own `preferredColorScheme` override, so only the
        /// screen still reports the device's appearance.
        func report() {
            guard let style = window?.windowScene?.screen.traitCollection.userInterfaceStyle
            else { return }
            onChange(style == .dark ? .dark : .light)
        }
    }
}
