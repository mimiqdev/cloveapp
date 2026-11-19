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
            metrics: DetailFilmstrip.Metrics
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
            .environment(\.cloveTheme, .light)

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

        let expectedAccent = try renderedAccentPixel(theme: .light)

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
            // Non-current neighbor slots do not shift by even a single pixel.
            #expect(baselineSpans[1] == standaloneSpans[1])
            #expect(baselineSpans[2] == standaloneSpans[2])
            #expect(baselineSpans[0] == stackSpans[0])
            #expect(baselineSpans[2] == stackSpans[2])
            // Current slot keeps exact leading edge and dimensions (<= 1 px anti-aliasing on stroked edge).
            #expect(baselineSpans[0].lowerBound == standaloneSpans[0].lowerBound)
            #expect(abs(baselineSpans[0].upperBound - standaloneSpans[0].upperBound) <= 1)
            #expect(baselineSpans[1].lowerBound == stackSpans[1].lowerBound)
            #expect(abs(baselineSpans[1].upperBound - stackSpans[1].upperBound) <= 1)

            let expectedWidthPx = Int(metrics.thumbnailWidth * 2)
            let expectedGapPx = Int(metrics.timelineSpacing * 2)
            for span in baselineSpans {
                #expect(abs((span.upperBound - span.lowerBound + 1) - expectedWidthPx) <= 1)
            }
            #expect(
                abs((baselineSpans[1].lowerBound - baselineSpans[0].upperBound - 1) - expectedGapPx)
                    <= 1)
            #expect(
                abs((baselineSpans[2].lowerBound - baselineSpans[1].upperBound - 1) - expectedGapPx)
                    <= 1)

            // Locator sits at the bottom inner edge of whichever slot is current without shifting neighbors.
            let locatorY = Int((metrics.bandHeight - metrics.verticalTrackPadding) * 2) - 5
            let firstCenterX = (baselineSpans[0].lowerBound + baselineSpans[0].upperBound) / 2
            let secondCenterX = (baselineSpans[1].lowerBound + baselineSpans[1].upperBound) / 2
            assertColorClose(
                withStandalone.pixel(x: firstCenterX, y: locatorY), expectedAccent,
                "standalone filmstrip locator")
            assertColorClose(
                withCollapsedStack.pixel(x: secondCenterX, y: locatorY), expectedAccent,
                "collapsed stack filmstrip locator")

            // Group Focus keeps identical member slot spans as current switches within the group.
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
        }
    }

    @Test func rejectedCurrentThumbnailsDimPhotoWhileKeepingFullOpacityAccentIndicator()
        async throws
    {
        let whiteThumb = solidCGImage(red: 1, green: 1, blue: 1)
        let photo = makePhoto("IND_REJ", isRejected: true, rating: .unrated)
        let nonRejectedPhoto = makePhoto("IND_OK", isRejected: false, rating: .unrated)
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
            let expectedAccent = try renderedAccentPixel(theme: theme)

            func renderFrame(_ target: GridPhoto) async throws -> PixelBuffer {
                let view = ZStack {
                    Color.black
                    DetailPhotoFrame(
                        photo: target, isCurrent: true, thumbnails: source, side: 54, height: 60)
                }
                .frame(width: 54, height: 60)
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
                    x: (390 - 54) / 2.0, y: (320 - 60) / 2.0, width: 54, height: 60)
                return try captureWindowRegion(region, in: window, scale: 2)
            }

            let normalPixels = try await renderFrame(nonRejectedPhoto)
            let rejectedPixels = try await renderFrame(photo)

            // Interior photo pixels dim when rejected.
            let normalInterior = normalPixels.pixel(x: 54, y: 60)
            let rejectedInterior = rejectedPixels.pixel(x: 54, y: 60)
            #expect(rejectedInterior.r < normalInterior.r)

            // Indicator outline and centered bottom locator stay full-opacity accent.
            assertColorClose(
                rejectedPixels.pixel(x: 54, y: 1), expectedAccent, "rejected top outline")
            assertColorClose(
                rejectedPixels.pixel(x: 54, y: 115), expectedAccent, "rejected bottom locator")
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
        let expectedAccent = try renderedAccentPixel(theme: theme)

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
            DetailPhotoFrame(
                photo: rated, isCurrent: true, thumbnails: source, side: 48, height: 48)
        }
        .frame(width: 48, height: 48)
        .ignoresSafeArea()
        .environment(\.cloveTheme, theme)

        let host = UIHostingController(rootView: view)
        host.safeAreaRegions = []
        host.view.backgroundColor = .black
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.layoutIfNeeded()
        #expect(
            host.sizeThatFits(in: CGSize(width: 200, height: 200)) == CGSize(width: 48, height: 48))
        try await Task.sleep(for: .milliseconds(80))

        let region = CGRect(x: (390 - 48) / 2.0, y: (320 - 48) / 2.0, width: 48, height: 48)
        let pixels = try captureWindowRegion(region, in: window, scale: 2)
        // Centered 14 × 2 pt bottom locator stays unobstructed across full width at inner bottom edge.
        assertColorClose(pixels.pixel(x: 48, y: 91), expectedAccent, "compact locator center")
        assertColorClose(pixels.pixel(x: 40, y: 91), expectedAccent, "compact locator left")
        assertColorClose(pixels.pixel(x: 56, y: 91), expectedAccent, "compact locator right")
        assertColorClose(pixels.pixel(x: 48, y: 1), expectedAccent, "compact top outline")
        // Rating pill renders cleanly above bottom inset, without colliding with bottom locator.
        #expect(!colorsClose(pixels.pixel(x: 16, y: 78), expectedAccent))
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
        let swatch = Rectangle()
            .fill(Color.clove.accent)
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
        _ actual: RGBA, _ expected: RGBA, _ label: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            colorsClose(actual, expected),
            "\(label): actual \(actual) != expected \(expected)",
            sourceLocation: sourceLocation)
    }

    private func colorsClose(_ actual: RGBA, _ expected: RGBA) -> Bool {
        abs(Int(actual.r) - Int(expected.r)) <= 10
            && abs(Int(actual.g) - Int(expected.g)) <= 10
            && abs(Int(actual.b) - Int(expected.b)) <= 10
            && abs(Int(actual.a) - Int(expected.a)) <= 10
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
