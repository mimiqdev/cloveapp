import SwiftUI

/// Reproduces the handoff's logical viewport on a supported phone simulator when its runtime
/// cannot create a Duo. This is available only in debug builds with the synthetic library.
struct DuoSampleViewport: ViewModifier {
    func body(content: Content) -> some View {
        #if DEBUG
            if ProcessInfo.processInfo.environment["CLOVE_TEST_LIBRARY"] == "1",
                ProcessInfo.processInfo.environment["CLOVE_TEST_DUO_VIEWPORT"] == "expanded"
            {
                GeometryReader { proxy in
                    content
                        .environment(\.horizontalSizeClass, .regular)
                        .environment(\.verticalSizeClass, .regular)
                        .frame(width: 900, height: 690)
                        .scaleEffect(min(proxy.size.width / 900, proxy.size.height / 690))
                        .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
                }
            } else {
                content
            }
        #else
            content
        #endif
    }
}
