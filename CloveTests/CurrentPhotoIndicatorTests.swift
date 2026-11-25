import CloveCore
import CoreGraphics
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct CurrentPhotoIndicatorTests {
    @Test func indicatorDrawsAccentOutlineAndCenteredBottomLocatorAcrossThemes() throws {
        for theme in [CloveTheme.light, CloveTheme.dark, CloveTheme.nord] {
            let expectedAccent = try renderedAccentPixel(theme: theme)
            let size = CGSize(width: 54, height: 60)
            let view = ZStack {
                Color.clear
                CurrentPhotoIndicator(cornerRadius: 6)
            }
            .frame(width: size.width, height: size.height)
            .environment(\.cloveTheme, theme)

            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            let pixels = try rgbaPixels(from: image)

            // 1.5 pt inset outline along all four sides.
            assertColorClose(pixels.pixel(x: 54, y: 1), expectedAccent, "top outline")
            assertColorClose(pixels.pixel(x: 1, y: 60), expectedAccent, "left outline")
            assertColorClose(pixels.pixel(x: 106, y: 60), expectedAccent, "right outline")
            assertColorClose(pixels.pixel(x: 54, y: 118), expectedAccent, "bottom outline")

            // Centered 14 × 2 pt bottom locator along inner bottom edge (1.5..3.5 pt from bottom).
            assertColorClose(pixels.pixel(x: 54, y: 115), expectedAccent, "bottom locator center")
            assertColorClose(pixels.pixel(x: 44, y: 115), expectedAccent, "bottom locator left")
            assertColorClose(pixels.pixel(x: 64, y: 115), expectedAccent, "bottom locator right")

            // Outside the 14 pt locator and inside the frame: transparent (no fill, glow, or tint).
            #expect(pixels.pixel(x: 24, y: 115).a == 0)
            #expect(pixels.pixel(x: 84, y: 115).a == 0)
            #expect(pixels.pixel(x: 54, y: 60).a == 0)
        }
    }

    @Test func indicatorAdaptsOutlineToCornerRadius() throws {
        let theme = CloveTheme.light
        let expectedAccent = try renderedAccentPixel(theme: theme)

        func renderCornerSample(cornerRadius: CGFloat) throws -> RGBA {
            let view = ZStack {
                Color.clear
                CurrentPhotoIndicator(cornerRadius: cornerRadius)
            }
            .frame(width: 60, height: 60)
            .environment(\.cloveTheme, theme)
            let renderer = ImageRenderer(content: view)
            renderer.scale = 2
            let image = try #require(renderer.cgImage)
            return try rgbaPixels(from: image).pixel(x: 1, y: 1)
        }

        // Square standalone grid tiles (radius 0) fill the outermost corner; rounded tiles do not.
        assertColorClose(try renderCornerSample(cornerRadius: 0), expectedAccent, "square corner")
        #expect(try renderCornerSample(cornerRadius: 5).a == 0)
        #expect(try renderCornerSample(cornerRadius: 6).a == 0)
    }

    @Test func filmstripMarkerDrawsOpaqueTwoToneCapsuleAcrossThemesAndBackgrounds() throws {
        for theme in [CloveTheme.light, CloveTheme.dark, CloveTheme.nord, CloveTheme.gruvbox] {
            #expect(
                hostedSize(FilmstripCurrentPhotoMarker().environment(\.cloveTheme, theme))
                    == CGSize(width: 12, height: 4))

            let expectedCore = try renderedColourPixel(Color.clove.text.primary, theme: theme)
            let expectedEdge = try renderedColourPixel(Color.clove.bg.canvas, theme: theme)

            let backdrops: [(String, AnyView, RGBA, RGBA)] = [
                (
                    "dark",
                    AnyView(Color.black),
                    RGBA(r: 0, g: 0, b: 0, a: 255),
                    RGBA(r: 0, g: 0, b: 0, a: 255)
                ),
                (
                    "bright",
                    AnyView(Color.white),
                    RGBA(r: 255, g: 255, b: 255, a: 255),
                    RGBA(r: 255, g: 255, b: 255, a: 255)
                ),
                (
                    "split",
                    AnyView(
                        HStack(spacing: 0) {
                            Color.black
                            Color.white
                        }
                    ),
                    RGBA(r: 0, g: 0, b: 0, a: 255),
                    RGBA(r: 255, g: 255, b: 255, a: 255)
                ),
            ]

            for (label, backdrop, leftCornerExpected, rightCornerExpected) in backdrops {
                let view = ZStack {
                    backdrop
                    FilmstripCurrentPhotoMarker()
                }
                .frame(width: 12, height: 4)
                .environment(\.cloveTheme, theme)

                let renderer = ImageRenderer(content: view)
                renderer.scale = 2
                let image = try #require(renderer.cgImage)
                let pixels = try rgbaPixels(from: image)

                // Opaque core in `text/primary` across dark, center, and bright spans.
                for x in [6, 12, 18] {
                    let core = pixels.pixel(x: x, y: 4)
                    #expect(core.a == 255)
                    assertColorClose(core, expectedCore, "\(theme.rawValue) \(label) core x=\(x)")
                }

                // Opaque 1 pt inside edge in `bg/canvas` around all sides.
                assertColorClose(
                    pixels.pixel(x: 12, y: 1), expectedEdge, "\(theme.rawValue) \(label) top edge")
                assertColorClose(
                    pixels.pixel(x: 12, y: 6), expectedEdge,
                    "\(theme.rawValue) \(label) bottom edge")
                assertColorClose(
                    pixels.pixel(x: 1, y: 4), expectedEdge, "\(theme.rawValue) \(label) left edge")
                assertColorClose(
                    pixels.pixel(x: 22, y: 4), expectedEdge,
                    "\(theme.rawValue) \(label) right edge")

                // Outside rounded corners, the underlying backdrop remains untouched.
                assertColorClose(
                    pixels.pixel(x: 0, y: 0), leftCornerExpected,
                    "\(theme.rawValue) \(label) outside top-left")
                assertColorClose(
                    pixels.pixel(x: 23, y: 7), rightCornerExpected,
                    "\(theme.rawValue) \(label) outside bottom-right")
            }
        }
    }

    @Test func indicatorPreservesTileDimensionsAndFilmstripSpacing() async throws {
        let whiteThumb = solidCGImage(red: 1, green: 1, blue: 1)
        let source = StaticThumbnailSource(image: whiteThumb)
        let first = makePhoto("IND0001")
        let second = makePhoto("IND0002")
        let third = makePhoto("IND0003")
        let fourth = makePhoto("IND0004")
        let groupID = GroupID(rawValue: "ind-group")
        let groups = [BrowsingGroup(id: groupID, members: [second.id, third.id])]
        let timeline = DetailTimeline(
            photos: [first, second, third, fourth], groups: groups, groupsEnabled: true)

        for (width, height) in [(CGFloat(54), CGFloat(60)), (CGFloat(48), CGFloat(48))] {
            let idleSize = hostedSize(
                DetailPhotoFrame(
                    photo: first, isCurrent: false, thumbnails: source, side: width, height: height
                )
                .environment(\.cloveTheme, .light))
            let currentSize = hostedSize(
                DetailPhotoFrame(
                    photo: first, isCurrent: true, thumbnails: source, side: width, height: height
                )
                .environment(\.cloveTheme, .light))
            #expect(idleSize == CGSize(width: width, height: height))
            #expect(currentSize == idleSize)
        }

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 140)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func captureFilmstrip(
            current: PhotoIdentity?, expanded: ActiveBrowsingGroup?,
            metrics: DetailFilmstrip.Metrics, theme: CloveTheme = .light
        ) async throws -> PixelBuffer {
            let strip = DetailFilmstrip(
                timeline: timeline,
                expandedGroup: expanded,
                current: current,
                thumbnails: source,
                metrics: metrics,
                openPhoto: { _ in },
                selectGroupPhoto: { _ in },
                expandGroup: { _ in },
                collapseGroup: {}
            )
            .frame(width: 390, height: metrics.bandHeight)
            .background(Color.black)
            .ignoresSafeArea()
            .environment(\.cloveTheme, theme)

            let host = UIHostingController(rootView: strip)
            host.safeAreaRegions = []
            host.view.backgroundColor = .black
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let region = CGRect(
                x: 0,
                y: (window.bounds.height - metrics.bandHeight) / 2.0,
                width: 390,
                height: metrics.bandHeight
            )
            return try captureWindowRegion(region, in: window, scale: 2)
        }

        func horizontalSlotSpans(in pixels: PixelBuffer, sampleY: Int) -> [ClosedRange<Int>] {
            var spans: [ClosedRange<Int>] = []
            var start: Int?
            for x in 0..<pixels.width {
                let px = pixels.pixel(x: x, y: sampleY)
                let isLit = px.r > 20 || px.g > 20 || px.b > 20
                if isLit {
                    if start == nil { start = x }
                } else if let openStart = start {
                    spans.append(openStart...(x - 1))
                    start = nil
                }
            }
            if let openStart = start {
                spans.append(openStart...(pixels.width - 1))
            }
            return spans
        }

        func verticalLitSpan(in pixels: PixelBuffer, sampleX: Int) -> ClosedRange<Int>? {
            var minY: Int?
            var maxY: Int?
            for y in 0..<pixels.height {
                let px = pixels.pixel(x: sampleX, y: y)
                let isLit = px.r > 120 && px.g > 120 && px.b > 120
                if isLit {
                    if minY == nil { minY = y }
                    maxY = y
                }
            }
            guard let minY, let maxY else { return nil }
            return minY...maxY
        }

        let expectedCore = try renderedColourPixel(Color.clove.text.primary, theme: .light)
        let expectedEdge = try renderedColourPixel(Color.clove.bg.canvas, theme: .light)
        let liftPx = Int(FilmstripCurrentPhotoMarker.lift * 2)  // 6 pt -> 12 px at 2x

        for metrics in [DetailFilmstrip.Metrics.standard, .compact] {
            let baseline = try await captureFilmstrip(
                current: nil, expanded: nil, metrics: metrics)
            let withStandalone = try await captureFilmstrip(
                current: first.id, expanded: nil, metrics: metrics)
            let withCollapsedStack = try await captureFilmstrip(
                current: second.id, expanded: nil, metrics: metrics)

            let midY = Int(metrics.bandHeight)  // scale 2: bandHeight * 2 / 2
            let baselineSpans = horizontalSlotSpans(in: baseline, sampleY: midY)
            let standaloneSpans = horizontalSlotSpans(in: withStandalone, sampleY: midY)
            let stackSpans = horizontalSlotSpans(in: withCollapsedStack, sampleY: midY)

            #expect(baselineSpans.count == 3)
            #expect(standaloneSpans.count == 3)
            #expect(stackSpans.count == 3)
            // Non-current neighbor slots do not shift horizontally by even a single pixel.
            #expect(baselineSpans[1] == standaloneSpans[1])
            #expect(baselineSpans[2] == standaloneSpans[2])
            #expect(baselineSpans[0] == stackSpans[0])
            #expect(baselineSpans[2] == stackSpans[2])
            // Current slot keeps exact horizontal span and dimensions.
            #expect(baselineSpans[0] == standaloneSpans[0])
            #expect(baselineSpans[1] == stackSpans[1])

            let expectedWidthPx = Int(metrics.thumbnailWidth * 2)
            let expectedGapPx = Int(DetailFilmstrip.thumbnailSpacing * 2)
            for span in baselineSpans {
                #expect(abs((span.upperBound - span.lowerBound + 1) - expectedWidthPx) <= 1)
            }
            #expect(
                abs((baselineSpans[1].lowerBound - baselineSpans[0].upperBound - 1) - expectedGapPx)
                    <= 1)
            #expect(
                abs((baselineSpans[2].lowerBound - baselineSpans[1].upperBound - 1) - expectedGapPx)
                    <= 1)

            // Vertical lift (6 pt) & two-tone marker (12 x 4 pt, 2 pt below) without shifting neighbors.
            let firstCenterX = (baselineSpans[0].lowerBound + baselineSpans[0].upperBound) / 2
            let secondCenterX = (baselineSpans[1].lowerBound + baselineSpans[1].upperBound) / 2
            let thirdCenterX = (baselineSpans[2].lowerBound + baselineSpans[2].upperBound) / 2

            let baseSoloY = try #require(verticalLitSpan(in: baseline, sampleX: firstCenterX - 24))
            let raisedSoloY = try #require(
                verticalLitSpan(in: withStandalone, sampleX: firstCenterX - 24))
            let neighborStackY = try #require(
                verticalLitSpan(in: withStandalone, sampleX: secondCenterX - 24))
            let baseStackY = try #require(
                verticalLitSpan(in: baseline, sampleX: secondCenterX - 24))
            let raisedStackY = try #require(
                verticalLitSpan(in: withCollapsedStack, sampleX: secondCenterX - 24))
            let neighborEndY = try #require(
                verticalLitSpan(in: withCollapsedStack, sampleX: thirdCenterX - 24))
            let baseEndY = try #require(verticalLitSpan(in: baseline, sampleX: thirdCenterX - 24))

            #expect(baseSoloY.lowerBound - raisedSoloY.lowerBound == liftPx)
            #expect(baseSoloY.upperBound - raisedSoloY.upperBound == liftPx)
            #expect(neighborStackY == baseStackY)

            // Raised stack includes peeking cards 4 pt above the cover; top peek must stay inside bandHeight.
            #expect(baseStackY.lowerBound - raisedStackY.lowerBound == liftPx)
            #expect(baseStackY.upperBound - raisedStackY.upperBound == liftPx)
            #expect(raisedStackY.lowerBound >= Int(metrics.verticalTrackPadding * 2))
            #expect(neighborEndY == baseEndY)

            // Marker spans the bottom 4 pt (8 px) of the slot, separated from the raised tile by a 2 pt (4 px) gap.
            let slotBottomPx = Int((metrics.bandHeight - metrics.verticalTrackPadding) * 2)
            let markerTopPx = slotBottomPx - 8
            #expect(raisedSoloY.upperBound + 1 == markerTopPx - 4)
            #expect(raisedStackY.upperBound + 1 == markerTopPx - 4)
            for centerX in [firstCenterX] {
                assertColorClose(
                    withStandalone.pixel(x: centerX, y: markerTopPx + 1), expectedEdge,
                    "standalone marker top 1 pt edge", tolerance: 30)
                assertColorClose(
                    withStandalone.pixel(x: centerX, y: markerTopPx + 4), expectedCore,
                    "standalone marker core")
                assertColorClose(
                    withStandalone.pixel(x: centerX, y: markerTopPx + 6), expectedEdge,
                    "standalone marker bottom 1 pt edge", tolerance: 30)
                // 2 pt gap between raised thumbnail and marker stays clear.
                #expect(withStandalone.pixel(x: centerX, y: markerTopPx - 2).r < 20)
            }
            assertColorClose(
                withCollapsedStack.pixel(x: secondCenterX, y: markerTopPx + 1), expectedEdge,
                "collapsed stack marker top 1 pt edge", tolerance: 30)
            assertColorClose(
                withCollapsedStack.pixel(x: secondCenterX, y: markerTopPx + 4), expectedCore,
                "collapsed stack marker core")
            assertColorClose(
                withCollapsedStack.pixel(x: secondCenterX, y: markerTopPx + 6), expectedEdge,
                "collapsed stack marker bottom 1 pt edge", tolerance: 30)
            #expect(withCollapsedStack.pixel(x: secondCenterX, y: markerTopPx - 2).r < 20)

            // Group Focus keeps identical member slot spans as current switches within the group,
            // raises only the current member by 6 pt, and renders the two-tone marker unclipped.
            let expandedGroup = try #require(timeline.activeGroup(with: groupID))
            let focusFirst = try await captureFilmstrip(
                current: second.id, expanded: expandedGroup, metrics: metrics)
            let focusSecond = try await captureFilmstrip(
                current: third.id, expanded: expandedGroup, metrics: metrics)
            let focusSpansFirst = horizontalSlotSpans(in: focusFirst, sampleY: midY)
            let focusSpansSecond = horizontalSlotSpans(in: focusSecond, sampleY: midY)
            #expect(focusSpansFirst.count >= 2)
            #expect(focusSpansFirst.count == focusSpansSecond.count)
            for (lhs, rhs) in zip(focusSpansFirst, focusSpansSecond) {
                #expect(abs(lhs.lowerBound - rhs.lowerBound) <= 1)
                #expect(abs(lhs.upperBound - rhs.upperBound) <= 1)
            }

            // Locate the two 54/48 pt member spans (skipping the 36 pt trailing glass button).
            let memberSpansFirst = focusSpansFirst.filter {
                abs(($0.upperBound - $0.lowerBound + 1) - expectedWidthPx) <= 1
            }
            let memberSpansSecond = focusSpansSecond.filter {
                abs(($0.upperBound - $0.lowerBound + 1) - expectedWidthPx) <= 1
            }
            #expect(memberSpansFirst.count == 2)
            #expect(memberSpansSecond.count == 2)
            #expect(
                abs(
                    (memberSpansFirst[1].lowerBound - memberSpansFirst[0].upperBound - 1)
                        - expectedGapPx)
                    <= 1)
            let m0CenterX = (memberSpansFirst[0].lowerBound + memberSpansFirst[0].upperBound) / 2
            let m1CenterX = (memberSpansFirst[1].lowerBound + memberSpansFirst[1].upperBound) / 2
            let firstSelectedY = try #require(
                verticalLitSpan(in: focusFirst, sampleX: m0CenterX - 24))
            let secondIdleY = try #require(
                verticalLitSpan(in: focusFirst, sampleX: m1CenterX - 24))
            let firstIdleY = try #require(
                verticalLitSpan(in: focusSecond, sampleX: m0CenterX - 24))
            let secondSelectedY = try #require(
                verticalLitSpan(in: focusSecond, sampleX: m1CenterX - 24))
            #expect(secondIdleY.lowerBound - firstSelectedY.lowerBound == liftPx)
            #expect(firstIdleY.lowerBound - secondSelectedY.lowerBound == liftPx)
            let focusMarkerTopPx = secondIdleY.upperBound + 1 - 8
            assertColorClose(
                focusFirst.pixel(x: m0CenterX, y: focusMarkerTopPx + 4), expectedCore,
                "group focus first member marker core")
            assertColorClose(
                focusFirst.pixel(x: m0CenterX, y: focusMarkerTopPx + 1), expectedEdge,
                "group focus first member marker edge", tolerance: 30)
            assertColorClose(
                focusSecond.pixel(x: m1CenterX, y: focusMarkerTopPx + 4), expectedCore,
                "group focus second member marker core")
            assertColorClose(
                focusSecond.pixel(x: m1CenterX, y: focusMarkerTopPx + 1), expectedEdge,
                "group focus second member marker edge", tolerance: 30)
        }
    }

    @Test func rejectedCurrentThumbnailsDimPhotoWhileKeepingFullOpacityTwoToneMarker()
        async throws
    {
        let whiteThumb = solidCGImage(red: 1, green: 1, blue: 1)
        let rejectedStandalone = makePhoto("IND_REJ", isRejected: true, rating: .unrated)
        let normalStandalone = makePhoto("IND_OK", isRejected: false, rating: .unrated)
        let rejectedMemberA = makePhoto("IND_G1", isRejected: true, rating: .unrated)
        let rejectedMemberB = makePhoto("IND_G2", isRejected: true, rating: .unrated)
        let groupID = GroupID(rawValue: "rej-group")
        let groups = [
            BrowsingGroup(id: groupID, members: [rejectedMemberA.id, rejectedMemberB.id])
        ]
        let timeline = DetailTimeline(
            photos: [normalStandalone, rejectedStandalone, rejectedMemberA, rejectedMemberB],
            groups: groups,
            groupsEnabled: true)
        let expandedGroup = try #require(timeline.activeGroup(with: groupID))
        let source = StaticThumbnailSource(image: whiteThumb)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 320)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let expectedCore = try renderedColourPixel(Color.clove.text.primary, theme: theme)
            let expectedEdge = try renderedColourPixel(Color.clove.bg.canvas, theme: theme)

            // 1. Standalone rejected DetailPhotoFrame dims pixels without drawing old accent outline.
            func renderRaisedTile(_ target: GridPhoto) async throws -> PixelBuffer {
                let view = ZStack {
                    Color.black
                    FilmstripRaisedTile(width: 54, baseHeight: 60, isCurrent: true) {
                        DetailPhotoFrame(
                            photo: target, isCurrent: true, thumbnails: source, side: 54,
                            height: 60)
                    }
                }
                .frame(width: 54, height: 66)
                .ignoresSafeArea()
                .environment(\.cloveTheme, theme)

                let host = UIHostingController(rootView: view)
                host.safeAreaRegions = []
                host.view.backgroundColor = .black
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                let region = CGRect(
                    x: (390 - 54) / 2.0, y: (320 - 66) / 2.0, width: 54, height: 66)
                return try captureWindowRegion(region, in: window, scale: 2)
            }

            let normalPixels = try await renderRaisedTile(normalStandalone)
            let rejectedPixels = try await renderRaisedTile(rejectedStandalone)

            // Interior photo pixels dim when rejected; top border has no accent outline.
            let normalInterior = normalPixels.pixel(x: 54, y: 60)
            let rejectedInterior = rejectedPixels.pixel(x: 54, y: 60)
            #expect(rejectedInterior.r < normalInterior.r)
            assertColorClose(
                rejectedPixels.pixel(x: 54, y: 1), rejectedInterior,
                "\(theme.rawValue) no inset accent outline")

            // Two-tone marker below the rejected thumbnail stays at full opacity 1.0.
            assertColorClose(
                rejectedPixels.pixel(x: 54, y: 125), expectedEdge,
                "\(theme.rawValue) rejected marker top edge", tolerance: 24)
            assertColorClose(
                rejectedPixels.pixel(x: 54, y: 128), expectedCore,
                "\(theme.rawValue) rejected marker core")
            assertColorClose(
                rejectedPixels.pixel(x: 54, y: 130), expectedEdge,
                "\(theme.rawValue) rejected marker bottom edge", tolerance: 24)

            // 2. All-rejected collapsed stack and rejected Group Focus member in DetailFilmstrip
            //    keep their two-tone marker at full opacity 1.0.
            let metrics = DetailFilmstrip.Metrics.standard
            func renderFilmstrip(
                current: PhotoIdentity, expanded: ActiveBrowsingGroup?
            ) async throws -> PixelBuffer {
                let strip = DetailFilmstrip(
                    timeline: timeline,
                    expandedGroup: expanded,
                    current: current,
                    thumbnails: source,
                    metrics: metrics,
                    openPhoto: { _ in },
                    selectGroupPhoto: { _ in },
                    expandGroup: { _ in },
                    collapseGroup: {}
                )
                .frame(width: 390, height: metrics.bandHeight)
                .background(Color(red: 0.5, green: 0.5, blue: 0.5))
                .ignoresSafeArea()
                .environment(\.cloveTheme, theme)

                let host = UIHostingController(rootView: strip)
                host.safeAreaRegions = []
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(120))
                let region = CGRect(
                    x: 0, y: (320 - metrics.bandHeight) / 2.0, width: 390,
                    height: metrics.bandHeight)
                return try captureWindowRegion(region, in: window, scale: 2)
            }

            let stackPixels = try await renderFilmstrip(current: rejectedMemberA.id, expanded: nil)
            // Timeline ScrollView is leading-aligned:
            // slot 0 [10..64], slot 1 [72..126], slot 2 (collapsed stack) [134..188] -> center = 161 pt = 322 px.
            let stackCenterPt =
                metrics.horizontalPadding
                + 2 * (metrics.thumbnailWidth + DetailFilmstrip.thumbnailSpacing)
                + metrics.thumbnailWidth / 2
            let stackCenterX = Int(stackCenterPt * 2)
            let slotBottomPx = Int((metrics.bandHeight - metrics.verticalTrackPadding) * 2)
            assertColorClose(
                stackPixels.pixel(x: stackCenterX, y: slotBottomPx - 4), expectedCore,
                "\(theme.rawValue) all-rejected stack marker core")
            assertColorClose(
                stackPixels.pixel(x: stackCenterX, y: slotBottomPx - 7), expectedEdge,
                "\(theme.rawValue) all-rejected stack marker edge", tolerance: 24)

            let groupPixels = try await renderFilmstrip(
                current: rejectedMemberA.id, expanded: expandedGroup)
            // Small Group Focus (2 members, no overflow -> no leading picker button):
            // [member 0 (54), spacing (3), member 1 (54), buttonSpacing (8), fold (36)] = 155 pt centered in 390 pt.
            // Tiles align identically at the bottom with `verticalTrackPadding`, matching Timeline.
            let groupTotalWidth =
                2 * metrics.thumbnailWidth
                + DetailFilmstrip.thumbnailSpacing
                + metrics.groupActionSpacing
                + metrics.groupActionButtonSize
            let groupMemberCenterPt = (390 - groupTotalWidth) / 2 + metrics.thumbnailWidth / 2
            let groupMemberCenterX = Int((groupMemberCenterPt * 2).rounded())
            assertColorClose(
                groupPixels.pixel(x: groupMemberCenterX, y: slotBottomPx - 4), expectedCore,
                "\(theme.rawValue) rejected group focus marker core")
            assertColorClose(
                groupPixels.pixel(x: groupMemberCenterX, y: slotBottomPx - 7), expectedEdge,
                "\(theme.rawValue) rejected group focus marker edge", tolerance: 24)
        }
    }

    @Test func splitGridCellAnchorsIndicatorToCoverCardGroupMemberAndStandaloneSquare()
        async throws
    {
        let whiteThumb = solidCGImage(red: 1, green: 1, blue: 1)
        let source = StaticThumbnailSource(image: whiteThumb)
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 400)
        window.rootViewController = UIViewController()
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let standalone = makePhoto("CELL_SOLO", isRejected: true)
        let coverPhoto = makePhoto("CELL_COVER", isRejected: true)
        let memberPhoto = makePhoto("CELL_MEMBER", isRejected: false)
        let groupID = GroupID(rawValue: "cell-group")

        let standaloneItem = GridCellItem(
            id: .photo(standalone.id), photo: standalone, group: nil, isDimmed: true)
        let coverItem = GridCellItem(
            id: .group(groupID), photo: coverPhoto,
            group: GridCellItem.GroupMark(
                id: groupID, count: 3, showsCount: true, isCover: true,
                peekingPhotos: [memberPhoto.id]),
            isDimmed: true)
        let memberItem = GridCellItem(
            id: .photo(memberPhoto.id), photo: memberPhoto,
            group: GridCellItem.GroupMark(
                id: groupID, count: 3, showsCount: false, isCover: false, peekingPhotos: []),
            isDimmed: false)

        for theme in [CloveTheme.light, CloveTheme.dark] {
            let expectedAccent = try renderedAccentPixel(theme: theme)

            func renderCell(_ item: GridCellItem) async throws -> PixelBuffer {
                // Place inside safe area so UIHostingConfiguration does not inset the cell.
                let cellFrame = CGRect(x: 40, y: 120, width: 100, height: 100)
                let cell = GridPhotoCell(frame: cellFrame)
                cell.backgroundColor = .black
                cell.configure(
                    with: item, isSelected: false, isCurrent: true, isSelecting: false,
                    thumbnails: source, theme: theme, onOpenGroup: { _ in })
                window.addSubview(cell)
                cell.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
                defer { cell.removeFromSuperview() }
                return try captureWindowRegion(cellFrame, in: window, scale: 2)
            }

            // 1. Standalone square tile (cornerRadius 0, dimmed photo, full-opacity accent).
            let soloPixels = try await renderCell(standaloneItem)
            assertColorClose(soloPixels.pixel(x: 1, y: 1), expectedAccent, "standalone corner")
            assertColorClose(
                soloPixels.pixel(x: 100, y: 195), expectedAccent, "standalone bottom locator")

            // 2. Collapsed stack (cover card starts at y = 8 pt -> 16 px; top peek edges have no border).
            let coverPixels = try await renderCell(coverItem)
            #expect(!colorsClose(coverPixels.pixel(x: 1, y: 4), expectedAccent))
            assertColorClose(
                coverPixels.pixel(x: 100, y: 17), expectedAccent, "cover top outline at peek=8")
            assertColorClose(
                coverPixels.pixel(x: 100, y: 195), expectedAccent, "cover bottom locator")

            // 3. Expanded group member (cornerRadius 6: corner (1, 1) is outside corner curve).
            let memberPixels = try await renderCell(memberItem)
            #expect(!colorsClose(memberPixels.pixel(x: 1, y: 1), expectedAccent))
            assertColorClose(
                memberPixels.pixel(x: 100, y: 1), expectedAccent, "member top outline")
            assertColorClose(
                memberPixels.pixel(x: 100, y: 195), expectedAccent, "member bottom locator")
        }
    }

    @Test func compactLandscapeFilmstripTileWithRatingKeepsIndicatorVisible() async throws {
        let source = StaticThumbnailSource(image: solidCGImage(red: 0.25, green: 0.3, blue: 0.35))
        let rated = makePhoto("IND_COMPACT", rating: Rating(rawValue: 5) ?? .unrated)
        let theme = CloveTheme.dark
        let expectedCore = try renderedColourPixel(Color.clove.text.primary, theme: theme)
        let expectedEdge = try renderedColourPixel(Color.clove.bg.canvas, theme: theme)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 320)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        let view = ZStack {
            Color.black
            FilmstripRaisedTile(width: 48, baseHeight: 48, isCurrent: true) {
                DetailPhotoFrame(
                    photo: rated, isCurrent: true, thumbnails: source, side: 48, height: 48)
            }
        }
        .frame(width: 48, height: 54)
        .ignoresSafeArea()
        .environment(\.cloveTheme, theme)

        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        #expect(
            host.sizeThatFits(in: CGSize(width: 200, height: 200)) == CGSize(width: 48, height: 54))
        try await Task.sleep(for: .milliseconds(80))

        let region = CGRect(x: (390 - 48) / 2.0, y: (320 - 54) / 2.0, width: 48, height: 54)
        let pixels = try captureWindowRegion(region, in: window, scale: 2)
        // Centered 12 × 4 pt two-tone marker renders 2 pt below the raised 48 × 48 thumbnail.
        assertColorClose(
            pixels.pixel(x: 48, y: 101), expectedEdge, "compact marker top edge", tolerance: 24)
        assertColorClose(pixels.pixel(x: 48, y: 104), expectedCore, "compact marker core")
        assertColorClose(
            pixels.pixel(x: 48, y: 106), expectedEdge, "compact marker bottom edge", tolerance: 24)
        // 2 pt gap between thumbnail bottom (96 px) and marker top (100 px) stays clear.
        #expect(pixels.pixel(x: 48, y: 98).r < 20)
        // Raised thumbnail reaches the top of the 54 pt slot without an inset accent outline.
        let topThumb = pixels.pixel(x: 48, y: 1)
        #expect(topThumb.r > 40 && topThumb.b > 60)
    }

    @Test func splitGridHighlightsCurrentPhotoWhileRegularGridStaysQuiet() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let darkSource = StaticThumbnailSource(
            image: solidCGImage(red: 0.2, green: 0.2, blue: 0.2))
        let library = TestLibrary.sample()
        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        try await waitUntil { !browsing.isFolderOpening }

        let standalone = try #require(
            browsing.photos.first { photo in
                !browsing.groups.contains { $0.members.contains(photo.id) }
            })
        let group = try #require(browsing.groups.first { $0.members.count >= 2 })
        let groupFirst = group.members[0]
        let groupSecond = group.members[1]
        let expectedAccent = try renderedAccentPixel(theme: .light)

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 320, height: 760)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        func captureCellBottomLocatorColor(
            at indexPath: IndexPath, in collectionView: UICollectionView
        ) throws -> RGBA {
            let cell = try #require(collectionView.cellForItem(at: indexPath))
            let frameInWindow = cell.convert(cell.bounds, to: window)
            let pixels = try captureWindowRegion(frameInWindow, in: window, scale: 2)
            let x = pixels.width / 2
            let y = pixels.height - 5
            return pixels.pixel(x: x, y: y)
        }

        // 1. SplitFolderGridPane highlights standalone, collapsed stack, and Group Focus members.
        browsing.openPhoto(standalone.id)
        let splitPane = SplitFolderGridPane(
            browsing: browsing,
            thumbnails: darkSource,
            similarGroupsEnabled: true,
            openPhoto: { browsing.openPhoto($0) },
            selectGroupPhoto: { browsing.selectGroupPhoto($0) },
            openGroup: { browsing.openGroup($0) },
            collapseGroup: { browsing.collapseGroup() }
        )
        .ignoresSafeArea()
        .environment(\.cloveTheme, .light)

        let splitHost = UIHostingController(rootView: splitPane)
        splitHost.safeAreaRegions = []
        window.rootViewController = splitHost
        window.makeKeyAndVisible()
        splitHost.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let splitCollection = try #require(
            findSubview(ofType: UICollectionView.self, in: window))
        // Cell (0, 0) is burst-2678 collapsed cover; cell (0, 1) is MMQ02680 standalone.
        let groupIndexPath = IndexPath(item: 0, section: 0)
        let soloIndexPath = IndexPath(item: 1, section: 0)

        assertColorClose(
            try captureCellBottomLocatorColor(at: soloIndexPath, in: splitCollection),
            expectedAccent, "split grid standalone highlighted")
        #expect(
            !colorsClose(
                try captureCellBottomLocatorColor(at: groupIndexPath, in: splitCollection),
                expectedAccent))

        browsing.openGroup(group.id)
        try await Task.sleep(for: .milliseconds(250))
        assertColorClose(
            try captureCellBottomLocatorColor(
                at: IndexPath(item: 0, section: 0), in: splitCollection),
            expectedAccent, "split grid focused first member highlighted")
        #expect(
            !colorsClose(
                try captureCellBottomLocatorColor(
                    at: IndexPath(item: 1, section: 0), in: splitCollection),
                expectedAccent))

        browsing.selectGroupPhoto(groupSecond)
        try await Task.sleep(for: .milliseconds(250))
        #expect(
            !colorsClose(
                try captureCellBottomLocatorColor(
                    at: IndexPath(item: 0, section: 0), in: splitCollection),
                expectedAccent))
        assertColorClose(
            try captureCellBottomLocatorColor(
                at: IndexPath(item: 1, section: 0), in: splitCollection),
            expectedAccent, "split grid focused second member highlighted")

        browsing.collapseGroup()
        try await Task.sleep(for: .milliseconds(250))
        assertColorClose(
            try captureCellBottomLocatorColor(at: groupIndexPath, in: splitCollection),
            expectedAccent, "split grid collapsed stack highlighted")
        #expect(
            !colorsClose(
                try captureCellBottomLocatorColor(at: soloIndexPath, in: splitCollection),
                expectedAccent))

        // 2. Regular GridScreen (highlightsCurrentPhoto == false) never draws the indicator.
        browsing.openPhoto(groupFirst)
        browsing.back()
        let gridRoot = NavigationStack {
            GridScreen(browsing: browsing, thumbnails: darkSource)
        }
        .environment(SettingsStore.sample)
        .environment(\.cloveUserInterfaceIdiom, .phone)
        .environment(\.cloveTheme, .light)

        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        let gridHost = UIHostingController(rootView: gridRoot)
        gridHost.safeAreaRegions = []
        window.rootViewController = gridHost
        window.makeKeyAndVisible()
        gridHost.view.layoutIfNeeded()
        try await Task.sleep(for: .milliseconds(250))

        let mainCollection = try #require(
            findSubview(ofType: UICollectionView.self, in: window))
        #expect(
            !colorsClose(
                try captureCellBottomLocatorColor(at: groupIndexPath, in: mainCollection),
                expectedAccent))
    }

    // MARK: - Helpers

    private func makePhoto(
        _ stem: String, isRejected: Bool = false, rating: Rating = .unrated
    ) -> GridPhoto {
        let id = PhotoIdentity(
            folderID: FolderIdentity(rawValue: "indicator-test"), relativeFolderPath: "", stem: stem
        )
        return GridPhoto(
            id: id,
            fileName: "\(stem).ARW",
            time: .unavailable,
            marks: PhotoMarks(rating: isRejected ? .rejected : rating))
    }

    private func hostedSize<V: View>(_ view: V) -> CGSize {
        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        return host.sizeThatFits(in: CGSize(width: 400, height: 400))
    }

    private func renderedAccentPixel(theme: CloveTheme) throws -> RGBA {
        try renderedColourPixel(Color.clove.accent, theme: theme)
    }

    private func renderedColourPixel(_ style: CloveColour, theme: CloveTheme) throws -> RGBA {
        let swatch = Rectangle()
            .fill(style)
            .frame(width: 10, height: 10)
            .environment(\.cloveTheme, theme)
        let renderer = ImageRenderer(content: swatch)
        renderer.scale = 1
        let image = try #require(renderer.cgImage)
        return try rgbaPixels(from: image).pixel(x: 5, y: 5)
    }

    private func captureWindowRegion(
        _ region: CGRect, in window: UIWindow, scale: CGFloat
    ) throws -> PixelBuffer {
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: region.size, format: format).image { context in
            context.cgContext.translateBy(x: -region.minX, y: -region.minY)
            didDraw = window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
        try #require(didDraw)
        return try rgbaPixels(from: try #require(image.cgImage))
    }

    private func solidCGImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return context.makeImage()!
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

    private func assertColorClose(
        _ actual: RGBA, _ expected: RGBA, _ label: String, tolerance: Int = 10,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            colorsClose(actual, expected, tolerance: tolerance),
            "\(label): actual \(actual) != expected \(expected)",
            sourceLocation: sourceLocation)
    }

    private func colorsClose(_ actual: RGBA, _ expected: RGBA, tolerance: Int = 10) -> Bool {
        abs(Int(actual.r) - Int(expected.r)) <= tolerance
            && abs(Int(actual.g) - Int(expected.g)) <= tolerance
            && abs(Int(actual.b) - Int(expected.b)) <= tolerance
            && abs(Int(actual.a) - Int(expected.a)) <= tolerance
    }

    private func findSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = findSubview(ofType: type, in: subview) { return match }
        }
        return nil
    }

    private func waitUntil(
        timeout: Duration = .seconds(3), condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline {
                Issue.record("timed out waiting for indicator test condition")
                return
            }
            try await Task.sleep(for: .milliseconds(20))
        }
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

@MainActor
private final class StaticThumbnailSource: GridThumbnailSource {
    private let image: CGImage?

    init(image: CGImage? = nil) {
        self.image = image
    }

    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? {
        image.map { .image($0) }
    }

    func companions(for photo: PhotoIdentity) -> GridCompanions { GridCompanions() }

    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority) async
        -> GridThumbnailOutcome
    {
        image.map { .image($0) } ?? .unavailable
    }
}
