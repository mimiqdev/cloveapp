import CloveCore
import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct GlassIconButtonTests {
    @Test func symbolTokenAndSizesMatchFigmaAndSystemToolbars() {
        #expect(GlassIconButton.symbolToken(isActive: true) == .accent)
        #expect(GlassIconButton.symbolToken(isActive: false) == .primaryText)
        #expect(GlassIconButton.symbolToken(isActive: nil) == .primaryText)

        #expect(GlassIconButton.diameter(for: .phone) == 44)
        #expect(GlassIconButton.diameter(for: .pad) == 40)
        #expect(GlassIconButton.diameter(for: .duo) == 36)

        for theme in CloveTheme.allCases {
            #expect(
                GlassIconButton.symbolColour(isActive: true, in: theme) == theme.tokens.accent.color
            )
            #expect(
                GlassIconButton.symbolColour(isActive: false, in: theme)
                    == theme.tokens.primaryText.color)
            #expect(
                GlassIconButton.symbolColour(isActive: nil, in: theme)
                    == theme.tokens.primaryText.color)
        }
    }

    @Test func activeStateUsesTranslucentGlassAndAccentSymbolWithoutSolidAccentFill() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)

        for theme in [CloveTheme.light, CloveTheme.dark, CloveTheme.nord] {
            let expectedAccent = try renderedPixel(theme.tokens.accent.color, theme: theme)
            let backdropColor = Color(red: 0.9, green: 0.15, blue: 0.35)
            let expectedBackdrop = try renderedPixel(backdropColor, theme: theme)

            let activePixels = try await renderHostedButton(
                isActive: true,
                theme: theme,
                backdrop: backdropColor,
                scene: scene)
            let inactivePixels = try await renderHostedButton(
                isActive: false,
                theme: theme,
                backdrop: backdropColor,
                scene: scene)

            // Center in 200x200 pt window at 2x scale is (200, 200) px; 44 pt circle has radius 44 px.
            // Corner outside the circle shows the underlying backdrop untouched.
            #expect(
                colorsClose(activePixels.pixel(x: 150, y: 150), expectedBackdrop, tolerance: 12))

            // Outer ring pixels inside the 44x44 circle (18 pt = 36 px from center, away from glyph)
            // must show translucent glass (differing from raw backdrop), must NOT be filled with
            // solid accent, and must match the inactive translucent glass circle.
            let ringSamples = [
                (x: 200, y: 164),
                (x: 164, y: 200),
                (x: 236, y: 200),
                (x: 200, y: 236),
            ]
            for sample in ringSamples {
                let activeSample = activePixels.pixel(x: sample.x, y: sample.y)
                let inactiveSample = inactivePixels.pixel(x: sample.x, y: sample.y)
                #expect(
                    !colorsClose(activeSample, expectedBackdrop, tolerance: 12),
                    "Expected rendered glass circle rather than raw backdrop at \(sample)"
                )
                #expect(
                    !colorsClose(activeSample, expectedAccent, tolerance: 18),
                    "Active GlassIconButton should not fill circle with solid accent at \(sample)"
                )
                #expect(
                    colorsClose(activeSample, inactiveSample, tolerance: 12),
                    "Active and inactive glass circle should share translucent backing at \(sample)"
                )
            }

            // Center glyph region of active button must differ from inactive button due to accent
            // symbol tinting while keeping outer ring identical.
            var hasAccentTintedDiff = false
            for y in 176..<224 {
                for x in 176..<224 {
                    let activePixel = activePixels.pixel(x: x, y: y)
                    let inactivePixel = inactivePixels.pixel(x: x, y: y)
                    if !colorsClose(activePixel, inactivePixel, tolerance: 20) {
                        hasAccentTintedDiff = true
                        break
                    }
                }
                if hasAccentTintedDiff { break }
            }
            #expect(hasAccentTintedDiff)
        }
    }

    private func renderHostedButton(
        isActive: Bool?,
        theme: CloveTheme,
        backdrop: Color,
        scene: UIWindowScene
    ) async throws -> PixelBuffer {
        let view = ZStack {
            backdrop
            GlassIconButton(
                label: "Filter",
                symbol: "line.3.horizontal.decrease",
                isActive: isActive,
                identifier: "test.glassIconButton"
            ) {}
        }
        .frame(width: 200, height: 200)
        .environment(\.cloveTheme, theme)
        .environment(\.colorScheme, theme.appearance.colorScheme)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 200, height: 200)
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.overrideUserInterfaceStyle = theme.appearance == .dark ? .dark : .light
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }
        host.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(100))

        let format = UIGraphicsImageRendererFormat()
        format.scale = 2
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: CGSize(width: 200, height: 200), format: format)
            .image { _ in
                didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
        try #require(didDraw)
        return try rgbaPixels(from: try #require(image.cgImage))
    }

    private func renderedPixel(_ color: Color, theme: CloveTheme) throws -> RGBA {
        let swatch = Rectangle()
            .fill(color)
            .frame(width: 8, height: 8)
            .environment(\.cloveTheme, theme)
        let renderer = ImageRenderer(content: swatch)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return try rgbaPixels(from: image).pixel(x: 4, y: 4)
    }

    private func rgbaPixels(from image: CGImage) throws -> PixelBuffer {
        let width = image.width
        let height = image.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = try #require(CGColorSpace(name: CGColorSpace.sRGB))
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = try #require(
            CGContext(
                data: &bytes, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: colorSpace, bitmapInfo: bitmapInfo))
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return PixelBuffer(width: width, height: height, bytes: bytes)
    }

    private func colorsClose(_ actual: RGBA, _ expected: RGBA, tolerance: Int) -> Bool {
        abs(Int(actual.r) - Int(expected.r)) <= tolerance
            && abs(Int(actual.g) - Int(expected.g)) <= tolerance
            && abs(Int(actual.b) - Int(expected.b)) <= tolerance
            && abs(Int(actual.a) - Int(expected.a)) <= tolerance
    }
}

private struct RGBA: CustomStringConvertible {
    let r: UInt8
    let g: UInt8
    let b: UInt8
    let a: UInt8

    var description: String { "(\(r), \(g), \(b), \(a))" }
}

private struct PixelBuffer {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    func pixel(x: Int, y: Int) -> RGBA {
        let offset = (y * width + x) * 4
        return RGBA(
            r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
    }
}
