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
        let splitWhiteImage = splitLeftRightSRGBImage(
            left: (1, 1, 1), right: (0.08, 0.08, 0.08))
        let splitCoralImage = splitLeftRightSRGBImage(
            left: (0.95, 0.35, 0.20), right: (0.08, 0.08, 0.08))
        let skyImage = solidSRGBImage(red: 0.15, green: 0.55, blue: 0.95)

        let whiteID = photoID("GRID_WHITE")
        let coralID = photoID("GRID_CORAL")
        let skyID = photoID("GRID_SKY")
        let peekID = photoID("GRID_PEEK")

        let source = MapThumbnailSource(images: [
            whiteID: splitWhiteImage,
            coralID: splitCoralImage,
            skyID: skyImage,
            peekID: splitWhiteImage,
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
            let normalWhiteSample = normalWhitePx.pixel(x: 60, y: 100)
            let rejectedWhiteSample = rejectedWhitePx.pixel(x: 60, y: 100)

            assertDarkroomNeutralWhiteSplit(
                brightHalf: rejectedWhiteSample,
                darkHalf: rejectedWhitePx.pixel(x: 140, y: 100),
                normalBrightHalf: normalWhiteSample,
                normalDarkHalf: normalWhitePx.pixel(x: 140, y: 100),
                context: "\(theme.rawValue) grid white")
            whiteRejectedRGBByTheme[theme] = rejectedWhiteSample

            let normalCoralPx = try await renderCell(normalCoral)
            let rejectedCoralPx = try await renderCell(rejectedCoral)
            assertDarkroomDesaturatedColor(
                rejectedCoralPx.pixel(x: 60, y: 100),
                normal: normalCoralPx.pixel(x: 60, y: 100),
                context: "\(theme.rawValue) grid coral")
            #expect(
                rejectedCoralPx.pixel(x: 140, y: 100).luminance <= 20,
                "\(theme.rawValue) grid coral loaded dark half")

            // Select mode unfolded tray tile uses the same neutral darkroom dimming without corner badges.
            let trayPosition = GridGroupTrayPosition(
                memberIndex: 1, memberCount: 2, connectsLeading: true, connectsTrailing: false)
            let selectTrayPx = try await renderCell(
                rejectedWhite, isSelecting: true, trayPosition: trayPosition)
            assertDarkroomNeutralWhiteSplit(
                brightHalf: selectTrayPx.pixel(x: 60, y: 100),
                darkHalf: selectTrayPx.pixel(x: 140, y: 100),
                normalBrightHalf: normalWhiteSample,
                normalDarkHalf: normalWhitePx.pixel(x: 140, y: 100),
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
            assertDarkroomNeutralWhiteSplit(
                brightHalf: coverPx.pixel(x: 60, y: 110),
                darkHalf: coverPx.pixel(x: 140, y: 110),
                normalBrightHalf: normalWhiteSample,
                normalDarkHalf: normalWhitePx.pixel(x: 140, y: 100),
                context: "\(theme.rawValue) grid stack cover")
            let peekBrightSample = coverPx.pixel(x: 50, y: 4)
            let peekDarkSample = coverPx.pixel(x: 150, y: 4)
            #expect(
                peekBrightSample.luminance >= 60 && peekBrightSample.luminance <= 105,
                "\(theme.rawValue) peeking card loaded bright half \(peekBrightSample)")
            #expect(
                peekDarkSample.luminance <= 18,
                "\(theme.rawValue) peeking card loaded dark half \(peekDarkSample)")
            #expect(
                peekBrightSample.luminance - peekDarkSample.luminance >= 50,
                "\(theme.rawValue) peeking card distinguishes loaded image from placeholder")
            #expect(peekBrightSample.chromaSpread <= 6, "\(theme.rawValue) peeking card untinted")

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
        let splitWhiteImage = splitLeftRightSRGBImage(
            left: (1, 1, 1), right: (0.08, 0.08, 0.08))
        let splitCoralImage = splitLeftRightSRGBImage(
            left: (0.95, 0.35, 0.20), right: (0.08, 0.08, 0.08))
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
            normalWhitePhoto.id: splitWhiteImage,
            rejectedWhitePhoto.id: splitWhiteImage,
            normalCoralPhoto.id: splitCoralImage,
            rejectedCoralPhoto.id: splitCoralImage,
            groupA.id: splitWhiteImage,
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
            assertDarkroomNeutralWhiteSplit(
                brightHalf: rejectedFrameWhite.pixel(x: 40, y: 72),
                darkHalf: rejectedFrameWhite.pixel(x: 92, y: 72),
                normalBrightHalf: normalFrameWhite.pixel(x: 40, y: 72),
                normalDarkHalf: normalFrameWhite.pixel(x: 92, y: 72),
                context: "\(theme.rawValue) DetailPhotoFrame white")

            let normalFrameCoral = try await renderFrame(normalCoralPhoto)
            let rejectedFrameCoral = try await renderFrame(rejectedCoralPhoto)
            let unDimmedRejectedCoral = try await renderFrame(
                rejectedCoralPhoto, appliesRejectedDimming: false)
            assertDarkroomDesaturatedColor(
                rejectedFrameCoral.pixel(x: 40, y: 72),
                normal: normalFrameCoral.pixel(x: 40, y: 72),
                context: "\(theme.rawValue) DetailPhotoFrame coral")
            #expect(
                rgbaDistance(
                    unDimmedRejectedCoral.pixel(x: 40, y: 72),
                    normalFrameCoral.pixel(x: 40, y: 72)) <= 4,
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

            assertDarkroomNeutralWhiteSplit(
                brightHalf: stripPx.pixel(x: slot1X - 24, y: tileMidY),
                darkHalf: stripPx.pixel(x: slot1X + 24, y: tileMidY),
                normalBrightHalf: stripPx.pixel(x: slot0X - 24, y: tileMidY),
                normalDarkHalf: stripPx.pixel(x: slot0X + 24, y: tileMidY),
                context: "\(theme.rawValue) filmstrip rejected")
            assertDarkroomNeutralWhiteSplit(
                brightHalf: stripPx.pixel(x: slot2X - 24, y: tileMidY),
                darkHalf: stripPx.pixel(x: slot2X + 24, y: tileMidY),
                normalBrightHalf: stripPx.pixel(x: slot0X - 24, y: tileMidY),
                normalDarkHalf: stripPx.pixel(x: slot0X + 24, y: tileMidY),
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

            let c00 = cellCenter(col: 0, row: 0)
            let c10 = cellCenter(col: 1, row: 0)
            let c20 = cellCenter(col: 2, row: 0)
            let c01 = cellCenter(col: 0, row: 1)

            assertDarkroomNeutralWhiteSplit(
                brightHalf: pickerPx.pixel(x: Int(c10.x) - 50, y: Int(c10.y)),
                darkHalf: pickerPx.pixel(x: Int(c10.x) + 50, y: Int(c10.y)),
                normalBrightHalf: pickerPx.pixel(x: Int(c00.x) - 50, y: Int(c00.y)),
                normalDarkHalf: pickerPx.pixel(x: Int(c00.x) + 50, y: Int(c00.y)),
                context: "\(theme.rawValue) GroupPicker white")
            assertDarkroomDesaturatedColor(
                pickerPx.pixel(x: Int(c01.x) - 50, y: Int(c01.y)),
                normal: pickerPx.pixel(x: Int(c20.x) - 50, y: Int(c20.y)),
                context: "\(theme.rawValue) GroupPicker coral")
            #expect(
                pickerPx.pixel(x: Int(c01.x) + 50, y: Int(c01.y)).luminance <= 20,
                "\(theme.rawValue) GroupPicker coral loaded dark half")

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

    @Test func compareFilmstripRejectedReferenceStaysDarkroomOpaqueAcrossLightThemes() async throws
    {
        let splitWhiteImage = splitLeftRightSRGBImage(
            left: (1, 1, 1), right: (0.08, 0.08, 0.08))
        let refRejected = makeGridPhoto(photoID("CMP_REF_REJ"), isRejected: true)
        let refNormal = makeGridPhoto(photoID("CMP_REF_OK"), isRejected: false)
        let challengerNormal = makeGridPhoto(photoID("CMP_CHAL_OK"), isRejected: false)

        let source = MapThumbnailSource(images: [
            refRejected.id: splitWhiteImage,
            refNormal.id: splitWhiteImage,
            challengerNormal.id: splitWhiteImage,
        ])

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 120, width: 220, height: 72)
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        for theme in Self.lightThemes {
            let stageUIColor = UIColor(theme.tokens.stage.color)

            func renderCompareStrip(reference: GridPhoto) async throws -> PixelBuffer {
                let strip = ZStack {
                    Rectangle().fill(Color.clove.bg.stage)
                    CompareFilmstrip(
                        photos: [reference, challengerNormal],
                        reference: reference.id,
                        challenger: challengerNormal.id,
                        activeSide: .challenger,
                        thumbnails: source,
                        onSelectCandidate: { _ in }
                    )
                }
                .frame(width: 220, height: 56)
                .ignoresSafeArea()
                .environment(\.cloveTheme, theme)

                let host = UIHostingController(rootView: strip)
                host.safeAreaRegions = []
                host.view.backgroundColor = stageUIColor
                window.backgroundColor = stageUIColor
                window.rootViewController = host
                window.makeKeyAndVisible()
                host.view.layoutIfNeeded()
                try await Task.sleep(for: .milliseconds(120))
                let region = CGRect(
                    x: 0, y: (window.bounds.height - 56) / 2, width: 220, height: 56)
                return try captureWindowRegion(region, in: window, scale: 2)
            }

            let rejectedStripPx = try await renderCompareStrip(reference: refRejected)
            // Slot 0 (Reference A, non-challenger): x = 4..48 pt (8..96 px), y = 9..53 pt (18..106 px).
            // Sample below the top-leading A badge at y = 35 pt (70 px).
            let refBright = rejectedStripPx.pixel(x: 34, y: 70)
            let refDark = rejectedStripPx.pixel(x: 70, y: 70)
            // Slot 1 (Challenger B, raised 6 pt): x = 51..95 pt (102..190 px), y = 3..47 pt (6..94 px).
            let chalBright = rejectedStripPx.pixel(x: 128, y: 58)
            let chalDark = rejectedStripPx.pixel(x: 164, y: 58)

            assertDarkroomNeutralWhiteSplit(
                brightHalf: refBright,
                darkHalf: refDark,
                normalBrightHalf: chalBright,
                normalDarkHalf: chalDark,
                context: "\(theme.rawValue) CompareFilmstrip rejected reference A")

            // Verify the 'A' role badge pill remains crisp and opaque over top-leading corner.
            let hasRolePill = hasMatchingPixel(
                in: rejectedStripPx,
                xRange: 8..<44,
                yRange: 18..<48,
                matching: RGBA(r: 255, g: 255, b: 255, a: 255),
                tolerance: 35)
            #expect(hasRolePill, "\(theme.rawValue) CompareFilmstrip A role badge stays crisp")

            // Non-rejected Reference A keeps the subtle 0.78 treatment (blended over stage).
            let normalStripPx = try await renderCompareStrip(reference: refNormal)
            let normalRefDark = normalStripPx.pixel(x: 70, y: 70)
            #expect(
                normalRefDark.luminance > refDark.luminance + 25,
                "\(theme.rawValue) non-rejected reference A retains 0.78 opacity vs opaque rejected dark half"
            )
        }
    }

    // MARK: - Assertions & Pixel Helpers

    private func assertDarkroomNeutralWhiteSplit(
        brightHalf: RGBA,
        darkHalf: RGBA,
        normalBrightHalf: RGBA,
        normalDarkHalf: RGBA,
        context: String,
        sourceLocation: SourceLocation = #_sourceLocation
    ) {
        assertDarkroomNeutralWhite(
            brightHalf,
            normal: normalBrightHalf,
            context: context,
            sourceLocation: sourceLocation)
        #expect(
            normalDarkHalf.luminance <= 35,
            Comment(
                rawValue: "\(context): expected dark half in normal split, got \(normalDarkHalf)"),
            sourceLocation: sourceLocation)
        #expect(
            darkHalf.luminance <= 22,
            Comment(rawValue: "\(context): expected dark half in dimmed split, got \(darkHalf)"),
            sourceLocation: sourceLocation)
        #expect(
            brightHalf.luminance - darkHalf.luminance >= 70,
            Comment(
                rawValue:
                    "\(context): split contrast too low (\(brightHalf) vs \(darkHalf)); placeholder leak?"
            ),
            sourceLocation: sourceLocation)
    }

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
            rejected.luminance >= 95 && rejected.luminance <= 126,
            Comment(
                rawValue:
                    "\(context): expected darkroom ~0.44 luminance (95...126), got \(rejected)"),
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

    private func splitLeftRightSRGBImage(
        left: (CGFloat, CGFloat, CGFloat),
        right: (CGFloat, CGFloat, CGFloat)
    ) -> CGImage {
        let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
        let bitmapInfo =
            CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue
        let context = CGContext(
            data: nil, width: 16, height: 16, bitsPerComponent: 8, bytesPerRow: 64,
            space: colorSpace, bitmapInfo: bitmapInfo)!
        context.setFillColor(red: left.0, green: left.1, blue: left.2, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 16))
        context.setFillColor(red: right.0, green: right.1, blue: right.2, alpha: 1)
        context.fill(CGRect(x: 8, y: 0, width: 8, height: 16))
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
