import CloveCore
import CloveImaging
import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
@Suite("Rejected thumbnail dimming", .serialized)
struct RejectedThumbnailDimmingTests {
    private static let lightThemes = CloveTheme.allCases.filter { $0.appearance == .light }

    @Test func gridAndSelectCellsDarkenAndDesaturateAcrossAllTwelveThemes() async throws {
        let whiteImage = solidSRGBImage(red: 1, green: 1, blue: 1)
        let coralImage = solidSRGBImage(red: 0.95, green: 0.35, blue: 0.20)
        let skyImage = solidSRGBImage(red: 0.15, green: 0.55, blue: 0.95)

        let whiteID = photoID("GRID_WHITE")
        let coralID = photoID("GRID_CORAL")
        let skyID = photoID("GRID_SKY")
        let peekID = photoID("GRID_PEEK")

        let source = MapThumbnailSource(images: [
            whiteID: whiteImage,
            coralID: coralImage,
            skyID: skyImage,
            peekID: whiteImage,
        ])

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

        var whiteRejectedRGBByTheme: [CloveTheme: RGBA] = [:]

        for theme in CloveTheme.allCases {
            window.backgroundColor = UIColor(theme.tokens.canvas.color)

            func renderCell(
                _ item: GridCellItem,
                isSelecting: Bool = false,
                trayPosition: GridGroupTrayPosition? = nil
            ) async throws -> PixelBuffer {
                let cellFrame = CGRect(x: 40, y: 120, width: 100, height: 100)
                let cell = GridPhotoCell(frame: cellFrame)
                cell.backgroundColor = UIColor(theme.tokens.canvas.color)
                cell.configure(
                    with: item,
                    isSelected: false,
                    isCurrent: false,
                    isSelecting: isSelecting,
                    trayPosition: trayPosition,
                    thumbnails: source,
                    theme: theme,
                    onOpenGroup: { _ in })
                window.addSubview(cell)
                cell.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(50))
                defer { cell.removeFromSuperview() }
                return try captureWindowRegion(cellFrame, in: window, scale: 2)
            }

            let normalWhite = GridCellItem(
                id: .photo(whiteID),
                photo: makeGridPhoto(whiteID),
                group: nil,
                isDimmed: false)
            let rejectedWhite = GridCellItem(
                id: .photo(whiteID),
                photo: makeGridPhoto(whiteID, isRejected: true),
                group: nil,
                isDimmed: true)
            let normalCoral = GridCellItem(
                id: .photo(coralID),
                photo: makeGridPhoto(coralID),
                group: nil,
                isDimmed: false)
            let rejectedCoral = GridCellItem(
                id: .photo(coralID),
                photo: makeGridPhoto(coralID, isRejected: true),
                group: nil,
                isDimmed: true)
            let rejectedSkyLabeled = GridCellItem(
                id: .photo(skyID),
                photo: makeGridPhoto(skyID, isRejected: true, label: .green),
                group: nil,
                isDimmed: true)

            let normalWhitePx = try await renderCell(normalWhite)
            let rejectedWhitePx = try await renderCell(rejectedWhite)
            let normalWhiteSample = normalWhitePx.pixel(x: 100, y: 100)
            let rejectedWhiteSample = rejectedWhitePx.pixel(x: 100, y: 100)

            assertDarkroomNeutralWhite(
                rejectedWhiteSample,
                normal: normalWhiteSample,
                context: "\(theme.rawValue) grid white")
            whiteRejectedRGBByTheme[theme] = rejectedWhiteSample

            let normalCoralPx = try await renderCell(normalCoral)
            let rejectedCoralPx = try await renderCell(rejectedCoral)
            assertDarkroomDesaturatedColor(
                rejectedCoralPx.pixel(x: 100, y: 100),
                normal: normalCoralPx.pixel(x: 100, y: 100),
                context: "\(theme.rawValue) grid coral")

            // Select mode unfolded tray tile uses the same neutral darkroom dimming without corner badges.
            let trayPosition = GridGroupTrayPosition(
                memberIndex: 1, memberCount: 2, connectsLeading: true, connectsTrailing: false)
            let selectTrayPx = try await renderCell(
                rejectedWhite, isSelecting: true, trayPosition: trayPosition)
            assertDarkroomNeutralWhite(
                selectTrayPx.pixel(x: 100, y: 100),
                normal: normalWhiteSample,
                context: "\(theme.rawValue) select tray white")

            // Collapsed group stack cover and peeking card stay darkroom-dimmed and neutral.
            let groupID = GroupID(rawValue: "darkroom-group")
            let coverItem = GridCellItem(
                id: .group(groupID),
                photo: makeGridPhoto(whiteID, isRejected: true),
                group: GridCellItem.GroupMark(
                    id: groupID, count: 2, showsCount: true, isCover: true,
                    peekingPhotos: [peekID]),
                isDimmed: true)
            let coverPx = try await renderCell(coverItem)
            assertDarkroomNeutralWhite(
                coverPx.pixel(x: 100, y: 110),
                normal: normalWhiteSample,
                context: "\(theme.rawValue) grid stack cover")
            let peekSample = coverPx.pixel(x: 100, y: 4)
            #expect(peekSample.luminance < 110, "\(theme.rawValue) peeking card dimmed over black")
            #expect(peekSample.chromaSpread <= 6, "\(theme.rawValue) peeking card untinted")

            // Zero corner reject flag badges, while colour label dots keep vivid colour.
            let rejectColor = try renderedColourPixel(Color.clove.reject, theme: theme)
            let skyLabeledPx = try await renderCell(rejectedSkyLabeled)
            for corner in [
                CGPoint(x: 14, y: 14),
                CGPoint(x: 186, y: 14),
                CGPoint(x: 14, y: 186),
            ] {
                let sample = skyLabeledPx.pixel(x: Int(corner.x), y: Int(corner.y))
                #expect(
                    rgbaDistance(sample, rejectColor) > 40,
                    "\(theme.rawValue) unexpected corner reject badge at \(corner)")
            }
            let greenDotColor = try renderedColourPixel(Color.clove.label.green, theme: theme)
            let hasGreenDot = hasMatchingPixel(
                in: skyLabeledPx,
                xRange: 170..<198,
                yRange: 170..<198,
                matching: greenDotColor,
                tolerance: 30)
            #expect(hasGreenDot, "\(theme.rawValue) colour label dot stays vivid on rejected tile")
        }

        // Identical white rejected photo must match across Light & Dark themes (no canvas/card tint).
        let baseline = try #require(whiteRejectedRGBByTheme[.dark])
        for theme in CloveTheme.allCases {
            let actual = try #require(whiteRejectedRGBByTheme[theme])
            #expect(
                rgbaDistance(actual, baseline) <= 8,
                "\(theme.rawValue) white rejected \(actual) diverged from dark \(baseline)")
        }
    }

    @Test func filmstripAndGroupPickerDarkenAndDesaturateAcrossAllSixLightThemes() async throws {
        let whiteImage = solidSRGBImage(red: 1, green: 1, blue: 1)
        let coralImage = solidSRGBImage(red: 0.95, green: 0.35, blue: 0.20)
        let skyImage = solidSRGBImage(red: 0.15, green: 0.55, blue: 0.95)

        let normalWhitePhoto = makeGridPhoto(photoID("FS_NORM_W"))
        let rejectedWhitePhoto = makeGridPhoto(photoID("FS_REJ_W"), isRejected: true)
        let normalCoralPhoto = makeGridPhoto(photoID("FS_NORM_C"))
        let rejectedCoralPhoto = makeGridPhoto(photoID("FS_REJ_C"), isRejected: true)
        let groupA = makeGridPhoto(photoID("FS_GA"), isRejected: true)
        let groupB = makeGridPhoto(photoID("FS_GB"), isRejected: true, label: .blue)
        let groupID = GroupID(rawValue: "light-dim-group")
        let groups = [BrowsingGroup(id: groupID, members: [groupA.id, groupB.id])]
        let timeline = DetailTimeline(
            photos: [normalWhitePhoto, rejectedWhitePhoto, groupA, groupB],
            groups: groups,
            groupsEnabled: true)
        let activeGroup = try #require(timeline.activeGroup(with: groupID))

        let source = MapThumbnailSource(images: [
            normalWhitePhoto.id: whiteImage,
            rejectedWhitePhoto.id: whiteImage,
            normalCoralPhoto.id: coralImage,
            rejectedCoralPhoto.id: coralImage,
            groupA.id: whiteImage,
            groupB.id: skyImage,
        ])

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 120, width: 444, height: 320)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for theme in Self.lightThemes {
            let stageUIColor = UIColor(theme.tokens.stage.color)

            // 1. Standalone DetailPhotoFrame over light stage background.
            func renderFrame(
                _ photo: GridPhoto, appliesRejectedDimming: Bool = true
            ) async throws -> PixelBuffer {
                let frameView = ZStack {
                    Rectangle().fill(Color.clove.bg.stage)
                    DetailPhotoFrame(
                        photo: photo,
                        isCurrent: false,
                        thumbnails: source,
                        side: 54,
                        height: 60,
                        appliesRejectedDimming: appliesRejectedDimming)
                }
                .frame(width: 66, height: 72)
                .ignoresSafeArea()
                .environment(\.cloveTheme, theme)

                let host = UIHostingController(rootView: frameView)
                host.safeAreaRegions = []
                host.view.backgroundColor = stageUIColor
                window.backgroundColor = stageUIColor
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(80))
                let region = CGRect(
                    x: (window.bounds.width - 66) / 2,
                    y: (window.bounds.height - 72) / 2,
                    width: 66,
                    height: 72)
                return try captureWindowRegion(region, in: window, scale: 2)
            }

            let normalFrameWhite = try await renderFrame(normalWhitePhoto)
            let rejectedFrameWhite = try await renderFrame(rejectedWhitePhoto)
            assertDarkroomNeutralWhite(
                rejectedFrameWhite.pixel(x: 66, y: 72),
                normal: normalFrameWhite.pixel(x: 66, y: 72),
                context: "\(theme.rawValue) DetailPhotoFrame white")

            let normalFrameCoral = try await renderFrame(normalCoralPhoto)
            let rejectedFrameCoral = try await renderFrame(rejectedCoralPhoto)
            let unDimmedRejectedCoral = try await renderFrame(
                rejectedCoralPhoto, appliesRejectedDimming: false)
            assertDarkroomDesaturatedColor(
                rejectedFrameCoral.pixel(x: 66, y: 72),
                normal: normalFrameCoral.pixel(x: 66, y: 72),
                context: "\(theme.rawValue) DetailPhotoFrame coral")
            #expect(
                rgbaDistance(
                    unDimmedRejectedCoral.pixel(x: 66, y: 72),
                    normalFrameCoral.pixel(x: 66, y: 72)) <= 4,
                "\(theme.rawValue) Focus/un-dimmed frame preserves full colour")

            // 2. DetailFilmstrip standalone rejected tile + all-rejected collapsed group stack over light stage.
            let metrics = DetailFilmstrip.Metrics.standard
            let stripView = DetailFilmstrip(
                timeline: timeline,
                expandedGroup: nil,
                current: normalWhitePhoto.id,
                thumbnails: source,
                metrics: metrics,
                openPhoto: { _ in },
                selectGroupPhoto: { _ in },
                expandGroup: { _ in },
                collapseGroup: {}
            )
            .frame(width: 390, height: metrics.bandHeight)
            .background(Color.clove.bg.stage)
            .ignoresSafeArea()
            .environment(\.cloveTheme, theme)

            let stripHost = UIHostingController(rootView: stripView)
            stripHost.safeAreaRegions = []
            stripHost.view.backgroundColor = stageUIColor
            window.rootViewController = stripHost
            window.makeKeyAndVisible()
            stripHost.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let stripRegion = CGRect(
                x: (window.bounds.width - 390) / 2,
                y: (window.bounds.height - metrics.bandHeight) / 2,
                width: 390,
                height: metrics.bandHeight)
            let stripPx = try captureWindowRegion(stripRegion, in: window, scale: 2)

            let slotStep = metrics.thumbnailWidth + DetailFilmstrip.thumbnailSpacing
            let slot0X = Int((metrics.horizontalPadding + metrics.thumbnailWidth / 2) * 2)
            let slot1X = Int(
                (metrics.horizontalPadding + slotStep + metrics.thumbnailWidth / 2) * 2)
            let slot2X = Int(
                (metrics.horizontalPadding + 2 * slotStep + metrics.thumbnailWidth / 2) * 2)
            let tileMidY = Int((metrics.bandHeight - metrics.verticalTrackPadding - 30) * 2)

            let stripNormal = stripPx.pixel(x: slot0X, y: tileMidY)
            let stripRejected = stripPx.pixel(x: slot1X, y: tileMidY)
            let stripRejectedStack = stripPx.pixel(x: slot2X, y: tileMidY)
            assertDarkroomNeutralWhite(
                stripRejected, normal: stripNormal,
                context: "\(theme.rawValue) filmstrip rejected")
            assertDarkroomNeutralWhite(
                stripRejectedStack, normal: stripNormal,
                context: "\(theme.rawValue) filmstrip all-rejected stack")

            // 3. GroupPhotoGridPicker over light sheet background.
            let pickerMembers = [
                normalWhitePhoto, rejectedWhitePhoto, normalCoralPhoto, rejectedCoralPhoto,
                groupB,
            ]
            let mixedPickerGroup = ActiveBrowsingGroup(
                group: BrowsingGroup(
                    id: GroupID(rawValue: "picker-mixed"),
                    members: pickerMembers.map(\.id)),
                visibleMembers: pickerMembers,
                representative: normalWhitePhoto)
            let pickerHeight = GroupPhotoGridPicker.popoverHeight(
                memberCount: mixedPickerGroup.visibleMembers.count, compactHeight: false)
            let pickerView = GroupPhotoGridPicker(
                group: mixedPickerGroup,
                current: nil,
                thumbnails: source,
                showsDoneButton: false,
                onSelect: { _ in }
            )
            .ignoresSafeArea()
            .environment(\.cloveTheme, theme)

            let pickerHost = UIHostingController(rootView: pickerView)
            pickerHost.safeAreaRegions = []
            pickerHost.traitOverrides.verticalSizeClass = .regular
            pickerHost.view.backgroundColor = UIColor(theme.tokens.sheet.color)
            window.frame = CGRect(
                x: 0, y: 120, width: GroupPhotoGridPicker.popoverWidth, height: pickerHeight)
            window.rootViewController = pickerHost
            window.makeKeyAndVisible()
            pickerHost.view.layoutIfNeeded()
            try await Task.sleep(for: .milliseconds(120))
            let pickerScroll = try #require(findSubview(ofType: UIScrollView.self, in: window))
            let pickerScrollFrame = pickerScroll.convert(pickerScroll.bounds, to: window)
            let pickerPx = try captureWindowRegion(window.bounds, in: window, scale: 2)

            let padding = GroupPhotoGridPicker.gridPadding
            let spacing = GroupPhotoGridPicker.gridSpacing
            let columns = CGFloat(GroupPhotoGridPicker.popoverColumns)
            let cellSide =
                (pickerScrollFrame.width - padding * 2 - (columns - 1) * spacing)
                / columns
            let step = cellSide + spacing
            func cellCenter(col: Int, row: Int) -> CGPoint {
                let x = pickerScrollFrame.minX + padding + CGFloat(col) * step + cellSide / 2
                let y = pickerScrollFrame.minY + padding + CGFloat(row) * step + cellSide / 2
                return CGPoint(x: x * 2, y: y * 2)
            }

            let pNormalWhite = pickerPx.pixel(at: cellCenter(col: 0, row: 0))
            let pRejectedWhite = pickerPx.pixel(at: cellCenter(col: 1, row: 0))
            let pNormalCoral = pickerPx.pixel(at: cellCenter(col: 2, row: 0))
            let pRejectedCoral = pickerPx.pixel(at: cellCenter(col: 0, row: 1))

            assertDarkroomNeutralWhite(
                pRejectedWhite, normal: pNormalWhite,
                context: "\(theme.rawValue) GroupPicker white")
            assertDarkroomDesaturatedColor(
                pRejectedCoral, normal: pNormalCoral,
                context: "\(theme.rawValue) GroupPicker coral")

            // Blue colour label dot on cell (col 1, row 1) stays vivid; no reject corner badge.
            let blueDotColor = try renderedColourPixel(Color.clove.label.blue, theme: theme)
            let dotCellOriginX = Int((pickerScrollFrame.minX + padding + step) * 2)
            let dotCellMaxX = Int((pickerScrollFrame.minX + padding + step + cellSide) * 2)
            let dotCellOriginY = Int((pickerScrollFrame.minY + padding + step) * 2)
            let dotCellMaxY = Int((pickerScrollFrame.minY + padding + step + cellSide) * 2)
            let hasBlueDot = hasMatchingPixel(
                in: pickerPx,
                xRange: (dotCellMaxX - 40)..<dotCellMaxX,
                yRange: (dotCellMaxY - 40)..<dotCellMaxY,
                matching: blueDotColor,
                tolerance: 35)
            let dotCenterSample = pickerPx.pixel(
                x: min(pickerPx.width - 1, dotCellMaxX - 18),
                y: min(pickerPx.height - 1, dotCellMaxY - 18))
            #expect(
                hasBlueDot,
                "\(theme.rawValue) GroupPicker blue dot missing (expected \(blueDotColor), sample \(dotCenterSample), scrollFrame \(pickerScrollFrame), bounds \(window.bounds))"
            )

            let rejectColor = try renderedColourPixel(Color.clove.reject, theme: theme)
            let cornerSample = pickerPx.pixel(x: dotCellOriginX + 12, y: dotCellOriginY + 12)
            #expect(
                rgbaDistance(cornerSample, rejectColor) > 40,
                "\(theme.rawValue) GroupPicker has no corner reject badge")
            _ = activeGroup
            window.frame = CGRect(x: 0, y: 120, width: 444, height: 320)
        }
    }

    @Test func moveRejectsExpandedQuickGridRestoresKeptPhotosAndDimsWillMovePhotos() async throws {
        let whiteImage = solidSRGBImage(red: 1, green: 1, blue: 1)
        let coralImage = solidSRGBImage(red: 0.95, green: 0.35, blue: 0.20)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for theme in [
            CloveTheme.light, CloveTheme.catppuccinLatte, CloveTheme.gruvboxLight,
            CloveTheme.darkroomLight, CloveTheme.nightLight, CloveTheme.nordLight, CloveTheme.dark,
        ] {
            let library = DarkroomTestLibrary(
                stems: ["p1", "p2"],
                rejected: ["p1", "p2"],
                imagesByStem: ["p1": whiteImage, "p2": coralImage])
            let browsing = BrowsingModel(library: library, similarGroupsEnabled: false)
            browsing.openFolder()
            library.finishScan()
            try await waitUntil("folder opened") {
                !browsing.isFolderOpening && browsing.photos.count == 2
            }

            let flow = MoveRejectsFlow(browsing: browsing)
            await flow.planIfNeeded(
                configuration: RejectMoveConfiguration(settings: SettingsStore.sample.settings))
            guard case .confirming = flow.stage else {
                Issue.record("Expected MoveRejectsFlow to enter confirming stage")
                return
            }

            let sheet = MoveRejectsSheet(flow: flow, initiallyExpanded: true)
                .ignoresSafeArea()
                .environment(SettingsStore.sample)
                .environment(\.appLanguage, .english)
                .environment(\.cloveTheme, theme)

            let host = UIHostingController(rootView: sheet)
            host.safeAreaRegions = []
            host.view.backgroundColor = UIColor(theme.tokens.sheet.color)
            window.backgroundColor = UIColor(theme.tokens.sheet.color)
            window.rootViewController = host
            window.makeKeyAndVisible()
            host.view.layoutIfNeeded()

            var scrollView: UIScrollView?
            try await waitUntil("MoveRejects keepGrid scroll view laid out") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                scrollView = findSubview(ofType: UIScrollView.self, in: window)
                return (scrollView?.bounds.width ?? 0) > 200
            }
            let gridScroll = try #require(scrollView)
            try await Task.sleep(for: .milliseconds(100))

            let scrollFrame = gridScroll.convert(gridScroll.bounds, to: window)
            let tileSide = (scrollFrame.width - 3 * 4) / 4
            let p1Center = CGPoint(
                x: (scrollFrame.minX + tileSide / 2) * 2,
                y: (scrollFrame.minY + tileSide / 2) * 2)
            let p2Center = CGPoint(
                x: (scrollFrame.minX + tileSide + 4 + tileSide / 2) * 2,
                y: (scrollFrame.minY + tileSide / 2) * 2)

            // Initially both are "will move": white photo is darkroom neutral, coral photo is dark + desaturated.
            let initialPx = try captureWindowRegion(window.bounds, in: window, scale: 2)
            let p1Initial = initialPx.pixel(at: p1Center)
            let p2Initial = initialPx.pixel(at: p2Center)
            let fullWhite = RGBA(r: 255, g: 255, b: 255, a: 255)
            let fullCoral = RGBA(r: 242, g: 89, b: 51, a: 255)

            assertDarkroomNeutralWhite(
                p1Initial, normal: fullWhite, context: "\(theme.rawValue) MoveRejects p1 will-move")
            assertDarkroomDesaturatedColor(
                p2Initial, normal: fullCoral, context: "\(theme.rawValue) MoveRejects p2 will-move")

            // Tap/keep p1: p1 restores full brightness while p2 stays darkroom-dimmed.
            let p1 = library.identity("p1")
            let p2 = library.identity("p2")
            flow.toggleKeep(p1)
            try await Task.sleep(for: .milliseconds(250))

            let keptWhitePx = try captureWindowRegion(window.bounds, in: window, scale: 2)
            let p1Kept = keptWhitePx.pixel(at: p1Center)
            let p2StillDim = keptWhitePx.pixel(at: p2Center)
            #expect(
                p1Kept.r >= 245 && p1Kept.g >= 245 && p1Kept.b >= 245,
                "\(theme.rawValue) kept white photo restores 100% brightness: \(p1Kept)")
            #expect(
                p1Kept.luminance > p2StillDim.luminance * 2.0,
                "\(theme.rawValue) kept vs will-move contrast: \(p1Kept) vs \(p2StillDim)")
            assertDarkroomDesaturatedColor(
                p2StillDim, normal: fullCoral,
                context: "\(theme.rawValue) MoveRejects p2 stays dimmed")

            // Toggle p1 back to will-move and keep p2: p2 restores 100% vivid coral while p1 dims.
            flow.toggleKeep(p1)
            flow.toggleKeep(p2)
            try await Task.sleep(for: .milliseconds(250))

            let keptCoralPx = try captureWindowRegion(window.bounds, in: window, scale: 2)
            let p1DimAgain = keptCoralPx.pixel(at: p1Center)
            let p2Kept = keptCoralPx.pixel(at: p2Center)
            assertDarkroomNeutralWhite(
                p1DimAgain, normal: fullWhite,
                context: "\(theme.rawValue) MoveRejects p1 dims again")
            #expect(
                rgbaDistance(p2Kept, fullCoral) <= 18,
                "\(theme.rawValue) kept coral photo restores full colour & brightness: \(p2Kept)")
            #expect(
                p2Kept.chromaSpread > p1DimAgain.chromaSpread + 120,
                "\(theme.rawValue) kept colourful tile stands out cleanly against dimmed tile")

            // Verify zero corner reject badge on both tiles.
            let rejectColor = try renderedColourPixel(Color.clove.reject, theme: theme)
            let p1Corner = keptCoralPx.pixel(
                x: Int((scrollFrame.minX + 6) * 2), y: Int((scrollFrame.minY + 6) * 2))
            #expect(
                rgbaDistance(p1Corner, rejectColor) > 40,
                "\(theme.rawValue) MoveRejects tile has no corner reject badge")
        }
    }

    // MARK: - Assertions & Pixel Helpers

    private func assertDarkroomNeutralWhite(
        _ rejected: RGBA,
        normal: RGBA,
        context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            normal.luminance >= 240,
            Comment(rawValue: "\(context): expected bright normal sample, got \(normal)"),
            sourceLocation: sourceLocation)
        #expect(
            rejected.luminance >= 80 && rejected.luminance <= 140,
            Comment(
                rawValue:
                    "\(context): expected darkroom ~0.44 luminance (80...140), got \(rejected)"),
            sourceLocation: sourceLocation)
        #expect(
            rejected.luminance < normal.luminance * 0.6,
            Comment(rawValue: "\(context): rejected \(rejected) did not darken from \(normal)"),
            sourceLocation: sourceLocation)
        #expect(
            rejected.chromaSpread <= 4,
            Comment(
                rawValue: "\(context): expected neutral untinted grey, got spread in \(rejected)"),
            sourceLocation: sourceLocation)
    }

    private func assertDarkroomDesaturatedColor(
        _ rejected: RGBA,
        normal: RGBA,
        context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        #expect(
            rejected.luminance < normal.luminance * 0.65,
            Comment(rawValue: "\(context): rejected \(rejected) not darker than \(normal)"),
            sourceLocation: sourceLocation)
        #expect(
            rejected.chromaSpread <= max(10, Int(Double(normal.chromaSpread) * 0.25)),
            Comment(
                rawValue:
                    "\(context): rejected \(rejected) not sufficiently desaturated vs \(normal)"),
            sourceLocation: sourceLocation)
    }

    private func photoID(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(
            folderID: FolderIdentity(rawValue: "darkroom-dimming-test"),
            relativeFolderPath: "",
            stem: stem)
    }

    private func makeGridPhoto(
        _ id: PhotoIdentity, isRejected: Bool = false, label: LabelColour? = nil
    ) -> GridPhoto {
        GridPhoto(
            id: id,
            fileName: "\(id.stem).ARW",
            time: .unavailable,
            marks: PhotoMarks(
                rating: isRejected ? .rejected : .unrated,
                label: label.map { ColourLabel(colour: $0) } ?? .clear))
    }

    private func solidSRGBImage(red: CGFloat, green: CGFloat, blue: CGFloat) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: colorSpace, bitmapInfo: bitmapInfo)!
        context.setFillColor(red: red, green: green, blue: blue, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        return context.makeImage()!
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

    private func hasMatchingPixel(
        in buffer: PixelBuffer,
        xRange: Range<Int>,
        yRange: Range<Int>,
        matching target: RGBA,
        tolerance: Int
    ) -> Bool {
        let clampedX = max(0, xRange.lowerBound)..<min(buffer.width, xRange.upperBound)
        let clampedY = max(0, yRange.lowerBound)..<min(buffer.height, yRange.upperBound)
        for y in clampedY {
            for x in clampedX {
                if rgbaDistance(buffer.pixel(x: x, y: y), target) <= tolerance {
                    return true
                }
            }
        }
        return false
    }

    private func rgbaDistance(_ lhs: RGBA, _ rhs: RGBA) -> Int {
        max(
            abs(Int(lhs.r) - Int(rhs.r)),
            abs(Int(lhs.g) - Int(rhs.g)),
            abs(Int(lhs.b) - Int(rhs.b)),
            abs(Int(lhs.a) - Int(rhs.a)))
    }

    private func findSubview<T: UIView>(ofType type: T.Type, in root: UIView) -> T? {
        if let match = root as? T { return match }
        for subview in root.subviews {
            if let match = findSubview(ofType: type, in: subview) { return match }
        }
        return nil
    }

    private func waitUntil(
        _ message: String,
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now >= deadline {
                Issue.record("Timed out: \(message)")
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

    var luminance: Double {
        0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }

    var chromaSpread: Int {
        Int(max(r, max(g, b))) - Int(min(r, min(g, b)))
    }

    var description: String { "(\(r), \(g), \(b), \(a))" }
}

private struct PixelBuffer: CustomStringConvertible {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    var description: String { "PixelBuffer(\(width)x\(height))" }

    func pixel(x: Int, y: Int) -> RGBA {
        let offset = (y * width + x) * 4
        return RGBA(
            r: bytes[offset], g: bytes[offset + 1], b: bytes[offset + 2], a: bytes[offset + 3])
    }

    func pixel(at point: CGPoint) -> RGBA {
        pixel(x: Int(point.x.rounded()), y: Int(point.y.rounded()))
    }
}

@MainActor
private final class MapThumbnailSource: GridThumbnailSource {
    private let images: [PhotoIdentity: CGImage]

    init(images: [PhotoIdentity: CGImage]) {
        self.images = images
    }

    func cachedThumbnail(for photo: PhotoIdentity) -> GridThumbnailOutcome? {
        images[photo].map { .image($0) }
    }

    func companions(for photo: PhotoIdentity) -> GridCompanions { GridCompanions() }

    func thumbnail(for photo: PhotoIdentity, priority: GridThumbnailPriority) async
        -> GridThumbnailOutcome
    {
        images[photo].map { .image($0) } ?? .unavailable
    }
}

@MainActor
private final class DarkroomTestLibrary: FolderLibrary {
    let folder: FolderIdentity
    private let recentID = UUID()
    var photos: [GridPhoto]
    var groups: [BrowsingGroup] = []
    let updates: AsyncStream<FolderLibraryUpdate>
    private let continuation: AsyncStream<FolderLibraryUpdate>.Continuation
    let thumbnails: any GridThumbnailSource

    init(stems: [String], rejected: Set<String>, imagesByStem: [String: CGImage]) {
        let folder = FolderIdentity(rawValue: recentID.uuidString)
        self.folder = folder
        (updates, continuation) = AsyncStream.makeStream()
        var mappedImages: [PhotoIdentity: CGImage] = [:]
        self.photos = stems.map { stem in
            let id = PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem)
            if let img = imagesByStem[stem] {
                mappedImages[id] = img
            }
            return GridPhoto(
                id: id,
                fileName: "\(stem).ARW",
                time: .unavailable,
                marks: PhotoMarks(rating: rejected.contains(stem) ? .rejected : .unrated))
        }
        self.thumbnails = MapThumbnailSource(images: mappedImages)
    }

    var recents: [RecentFolder] {
        [RecentFolder(id: recentID, bookmark: Data(), pathSummary: "/Library", lastOpened: Date())]
    }

    func identity(_ stem: String) -> PhotoIdentity {
        PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem)
    }

    func finishScan() {
        continuation.yield(.photos(photos))
        continuation.yield(
            .scanFinished(FolderScanSummary(photoCount: photos.count, status: .complete)))
    }

    func scannedSet(for photo: PhotoIdentity) -> ScannedPhotoSet? {
        guard
            let set = try? PhotoSet(
                folderID: folder, relativeFolderPath: "",
                rawURL: URL(fileURLWithPath: "/Library/\(photo.stem).ARW"))
        else { return nil }
        return ScannedPhotoSet(photoSet: set, sidecar: .absent, imageFiles: [])
    }

    func planRejectMove(
        configuration: RejectMoveConfiguration, rejected: [PhotoIdentity]
    ) async throws -> RejectMovePlan {
        let root = URL(fileURLWithPath: "/Library")
        let destination = root.appendingPathComponent("_Rejected")
        let sets = rejected.compactMap { scannedSet(for: $0) }
        return RejectMovePlan(
            rootURL: root,
            configuration: configuration,
            sets: sets,
            entries: sets.map { set in
                .ready(
                    RejectMoveSetPlan(
                        identity: set.id,
                        relativeFolderPath: "",
                        destinationFolder: destination,
                        files: [
                            RejectMoveFilePlan(
                                role: .primary,
                                source: set.photoSet.primary.url,
                                destination: destination.appendingPathComponent(
                                    set.photoSet.primary.url.lastPathComponent))
                        ]))
            },
            destinationURL: destination)
    }
}
