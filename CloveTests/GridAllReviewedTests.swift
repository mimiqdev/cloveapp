import CloveCore
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@Suite("Grid all-reviewed completion state", .serialized)
@MainActor
struct GridAllReviewedTests {
    @Test func unmarkedEmptyingResolvesAllReviewedWhileAllAndOtherFiltersDoNot() async throws {
        let folder = TestLibrary.sampleFolderKey
        let fourStars = try #require(Rating(rawValue: 4))
        let photos = [
            makePhoto(
                folder: folder, stem: "p1", seconds: 1,
                marks: PhotoMarks(rating: fourStars),
                metadata: PhotoFilterMetadata(camera: "ILCE-1M2")),
            makePhoto(
                folder: folder, stem: "p2", seconds: 2,
                marks: PhotoMarks(rating: .rejected),
                metadata: PhotoFilterMetadata(camera: "ILCE-7M4")),
            makePhoto(
                folder: folder, stem: "p3", seconds: 3,
                marks: PhotoMarks(),
                metadata: PhotoFilterMetadata(camera: "ILCE-1M2")),
        ]
        let library = TestLibrary(photos: photos, groups: [])
        let model = BrowsingModel(library: library, similarGroupsEnabled: false)
        model.openFolder()
        // While scanFinished has not yet arrived, folder is opening and must never show allReviewed.
        #expect(
            GridEmptyStateKind.resolve(browsing: model, moveRejectsEnabled: true)
                == .filteredEmpty(isOpening: true, canClearFilters: false))
        try await waitFor("folder did not finish opening") { !model.isFolderOpening }

        // Default All filter: marking the last unmarked photo never triggers completion state.
        #expect(model.state.filter == .all)
        model.apply(.rating(fourStars), to: photos[2].id)
        await model.drainActions()
        #expect(model.photos.count == 3)
        #expect(model.state.filter == .all)
        #expect(
            GridEmptyStateKind.resolve(browsing: model, moveRejectsEnabled: true)
                == .filteredEmpty(isOpening: false, canClearFilters: false))

        // Restore p3 to unmarked and switch to Unmarked filter.
        model.apply(.rating(.unrated), to: photos[2].id)
        await model.drainActions()
        model.setFilter(.unmarked)
        #expect(model.photos.map(\.id.stem) == ["p3"])

        // Unmarked + metadata filter emptying is a generic no-match, not all-reviewed.
        model.toggleCameraFilter("ILCE-7M4")
        #expect(model.photos.isEmpty)
        #expect(
            GridEmptyStateKind.resolve(browsing: model, moveRejectsEnabled: true)
                == .filteredEmpty(isOpening: false, canClearFilters: true))

        // Clear metadata filter so only Unmarked is active, then mark the last unmarked photo.
        model.clearMetadataFilter()
        #expect(model.photos.map(\.id.stem) == ["p3"])
        model.apply(.rating(fourStars), to: photos[2].id)
        await model.drainActions()
        #expect(model.photos.isEmpty)

        let expectedSummary = GridReviewSummary(
            totalCount: 3,
            highRatedCount: 2,
            ratedCount: 2,
            labelledOnlyCount: 0,
            rejectedCount: 1,
            moveRejectsEnabled: true)
        #expect(
            GridEmptyStateKind.resolve(browsing: model, moveRejectsEnabled: true)
                == .allReviewed(expectedSummary))

        // Unmarked + labelFilter synthetic guard never shows allReviewed.
        #expect(
            GridEmptyStateKind.resolve(
                isFolderOpening: false,
                hasFolderContents: true,
                visiblePhotoCount: 0,
                filter: .unmarked,
                labelFilter: .green,
                metadataFilter: .none,
                hasActiveFilter: true,
                placedPhotos: model.allPlacedPhotos,
                rejectedPhotoCount: 1,
                moveRejectsEnabled: true)
                == .filteredEmpty(isOpening: false, canClearFilters: true))

        // Other empty filters (e.g. Rated 5★ when none are 5★) stay generic filteredEmpty.
        let fiveStars = try #require(Rating(rawValue: 5))
        model.setFilter(.ratedAtLeast(fiveStars))
        #expect(model.photos.isEmpty)
        #expect(
            GridEmptyStateKind.resolve(browsing: model, moveRejectsEnabled: true)
                == .filteredEmpty(isOpening: false, canClearFilters: true))

        // Show all photos behavior via setFilter(.all) restores full folder grid.
        model.setFilter(.all)
        #expect(model.state.filter == .all)
        #expect(!model.hasActiveFilter)
        #expect(model.photos.count == 3)

        // Empty folder and opening folder states never resolve to allReviewed.
        #expect(
            GridEmptyStateKind.resolve(
                isFolderOpening: false,
                hasFolderContents: false,
                visiblePhotoCount: 0,
                filter: .unmarked,
                labelFilter: nil,
                metadataFilter: .none,
                hasActiveFilter: true,
                placedPhotos: [],
                rejectedPhotoCount: 0,
                moveRejectsEnabled: true) == .emptyFolder)

        #expect(
            GridEmptyStateKind.resolve(
                isFolderOpening: true,
                hasFolderContents: true,
                visiblePhotoCount: 0,
                filter: .unmarked,
                labelFilter: nil,
                metadataFilter: .none,
                hasActiveFilter: true,
                placedPhotos: model.allPlacedPhotos,
                rejectedPhotoCount: 1,
                moveRejectsEnabled: true)
                == .filteredEmpty(isOpening: true, canClearFilters: false))
    }

    @Test func summaryCopyHandlesAllMarkBucketsPluralsAndLocalizations() {
        let single = GridReviewSummary(
            totalCount: 1, highRatedCount: 1, ratedCount: 1, labelledOnlyCount: 0,
            rejectedCount: 0, moveRejectsEnabled: true)
        #expect(single.localizedTitle(language: .english) == "1 photo reviewed")
        #expect(single.localizedTitle(language: .simplifiedChinese) == "1 张照片已审阅")
        #expect(single.localizedTitle(language: .traditionalChinese) == "1 張相片已審閱")
        #expect(single.localizedSubtitle(language: .english) == "1 ★4+")
        #expect(single.localizedSubtitle(language: .simplifiedChinese) == "1 张 ★4+")
        #expect(!single.offersMoveRejects)

        let standard = GridReviewSummary(
            totalCount: 24, highRatedCount: 12, ratedCount: 16, labelledOnlyCount: 0,
            rejectedCount: 5, moveRejectsEnabled: true)
        #expect(standard.localizedTitle(language: .english) == "All 24 photos reviewed")
        #expect(standard.localizedTitle(language: .simplifiedChinese) == "全部 24 张照片已审阅")
        #expect(standard.localizedTitle(language: .traditionalChinese) == "全部 24 張相片已審閱")
        #expect(standard.localizedSubtitle(language: .english) == "12 ★4+ · 5 rejected")
        #expect(standard.localizedSubtitle(language: .simplifiedChinese) == "12 张 ★4+ · 5 张已淘汰")
        #expect(standard.localizedSubtitle(language: .traditionalChinese) == "12 張 ★4+ · 5 張已淘汰")
        #expect(standard.localizedMoveRejectsTitle(language: .english) == "Move 5 rejects")
        #expect(standard.localizedMoveRejectsTitle(language: .simplifiedChinese) == "整理 5 张淘汰片")
        #expect(standard.localizedMoveRejectsTitle(language: .traditionalChinese) == "整理 5 張淘汰片")
        #expect(standard.localizedShowAllTitle(language: .english) == "Show all photos")
        #expect(standard.localizedShowAllTitle(language: .simplifiedChinese) == "显示全部照片")
        #expect(standard.localizedShowAllTitle(language: .traditionalChinese) == "顯示全部相片")
        #expect(standard.offersMoveRejects)

        let formattedLarge = GridReviewSummary(
            totalCount: 1240, highRatedCount: 300, ratedCount: 300, labelledOnlyCount: 0,
            rejectedCount: 1, moveRejectsEnabled: true)
        #expect(formattedLarge.localizedTitle(language: .english) == "All 1,240 photos reviewed")
        #expect(
            formattedLarge.localizedTitle(language: .simplifiedChinese) == "全部 1,240 张照片已审阅")
        #expect(formattedLarge.localizedMoveRejectsTitle(language: .english) == "Move 1 reject")
        #expect(
            formattedLarge.localizedMoveRejectsTitle(language: .simplifiedChinese)
                == "整理 1 张淘汰片")

        let rejectsOnly = GridReviewSummary(
            totalCount: 5, highRatedCount: 0, ratedCount: 0, labelledOnlyCount: 0,
            rejectedCount: 5, moveRejectsEnabled: false)
        #expect(rejectsOnly.localizedSubtitle(language: .english) == "5 rejected")
        #expect(rejectsOnly.localizedSubtitle(language: .simplifiedChinese) == "5 张已淘汰")
        #expect(!rejectsOnly.offersMoveRejects)

        let lowRatedAndRejects = GridReviewSummary(
            totalCount: 13, highRatedCount: 0, ratedCount: 8, labelledOnlyCount: 0,
            rejectedCount: 5, moveRejectsEnabled: true)
        #expect(lowRatedAndRejects.localizedSubtitle(language: .english) == "8 rated · 5 rejected")
        #expect(
            lowRatedAndRejects.localizedSubtitle(language: .simplifiedChinese)
                == "8 张已评分 · 5 张已淘汰")

        let lowRatedOnly = GridReviewSummary(
            totalCount: 8, highRatedCount: 0, ratedCount: 8, labelledOnlyCount: 0,
            rejectedCount: 0, moveRejectsEnabled: true)
        #expect(lowRatedOnly.localizedSubtitle(language: .english) == "8 rated")
        #expect(lowRatedOnly.localizedSubtitle(language: .simplifiedChinese) == "8 张已评分")

        let labelledOnly = GridReviewSummary(
            totalCount: 6, highRatedCount: 0, ratedCount: 0, labelledOnlyCount: 6,
            rejectedCount: 0, moveRejectsEnabled: true)
        #expect(labelledOnly.localizedSubtitle(language: .english) == "6 labeled")
        #expect(labelledOnly.localizedSubtitle(language: .simplifiedChinese) == "6 张已加标签")
        #expect(labelledOnly.localizedSubtitle(language: .traditionalChinese) == "6 張已加標籤")

        let labelledAndRejected = GridReviewSummary(
            totalCount: 11, highRatedCount: 0, ratedCount: 0, labelledOnlyCount: 6,
            rejectedCount: 5, moveRejectsEnabled: true)
        #expect(
            labelledAndRejected.localizedSubtitle(language: .english) == "6 labeled · 5 rejected")
        #expect(
            labelledAndRejected.localizedSubtitle(language: .simplifiedChinese)
                == "6 张已加标签 · 5 张已淘汰")
    }

    @Test func pillForegroundsMaintainAccessibleContrastAcrossAllTwelveThemes() {
        for theme in CloveTheme.allCases {
            for fill in [theme.tokens.reject, theme.tokens.accent] {
                let foreground = GridAllReviewedView.pillForegroundToken(on: fill, in: theme)
                let ratio = GridAllReviewedView.contrastRatio(fill, foreground)
                #expect(
                    ratio >= 3.5,
                    "Contrast ratio \(ratio) too low for theme \(theme.id)")
            }
        }
        // Dark pastel accents and Catppuccin Mocha reject must select dark canvas ink, not white.
        let mochaRejectInk = GridAllReviewedView.pillForegroundToken(
            on: CloveTheme.catppuccinMocha.tokens.reject, in: .catppuccinMocha)
        #expect(mochaRejectInk == CloveTheme.catppuccinMocha.tokens.canvas)
    }

    @Test func hostedGridScreenShowsAllReviewedOnlyForUnmarkedEmptyingAndRestoresOnShowAll()
        async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let folder = TestLibrary.sampleFolderKey
        let fourStars = try #require(Rating(rawValue: 4))
        let photos = [
            makePhoto(
                folder: folder, stem: "p1", seconds: 1,
                marks: PhotoMarks(rating: fourStars),
                metadata: PhotoFilterMetadata(camera: "ILCE-1M2")),
            makePhoto(
                folder: folder, stem: "p2", seconds: 2,
                marks: PhotoMarks(rating: .rejected),
                metadata: PhotoFilterMetadata(camera: "ILCE-7M4")),
            makePhoto(
                folder: folder, stem: "p3", seconds: 3,
                marks: PhotoMarks(),
                metadata: PhotoFilterMetadata(camera: "ILCE-1M2")),
        ]
        let library = TestLibrary(photos: photos, groups: [])
        let model = BrowsingModel(library: library, similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not finish opening") { !model.isFolderOpening }

        let store = SettingsStore.sample
        store.update { $0.moveRejectsEnabled = true }

        let framesBox = AllReviewedFrameStore()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 844)
        let host = UIHostingController(
            rootView: GridScreen(browsing: model, thumbnails: model.thumbnails)
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .phone)
                .environment(\.cloveTheme, .light)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    framesBox.frames = $0
                })
        host.traitOverrides.horizontalSizeClass = .compact
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        // 1. Default All filter: marking the last unmarked photo keeps grid visible with no completion state.
        try await waitFor("initial grid did not mount") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return self.findCollectionView(in: window) != nil
        }
        model.apply(.rating(fourStars), to: photos[2].id)
        await model.drainActions()
        try await Task.sleep(for: .milliseconds(60))
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        #expect(self.findCollectionView(in: window) != nil)
        #expect(framesBox.frames["clove.grid.allReviewed"] == nil)

        // 2. Restore p3 unmarked, switch to Unmarked, and mark p3 -> dedicated all-reviewed state mounts.
        model.apply(.rating(.unrated), to: photos[2].id)
        await model.drainActions()
        model.setFilter(.unmarked)
        try await waitFor("unmarked grid did not mount") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return self.findCollectionView(in: window)?.visibleCells.count == 1
        }
        model.apply(.rating(fourStars), to: photos[2].id)
        await model.drainActions()

        try await waitFor("all-reviewed state did not mount") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return framesBox.frames["clove.grid.allReviewed"] != nil
                && framesBox.frames["clove.grid.allReviewed.moveRejects"] != nil
                && framesBox.frames["clove.grid.allReviewed.showAll"] != nil
        }
        #expect(framesBox.frames["clove.grid.empty"] == nil)
        #expect(framesBox.frames["clove.grid.moveRejects"] == nil)

        // 3. Disabling Move Rejects hides Move rejects pill while keeping Show all photos.
        store.update { $0.moveRejectsEnabled = false }
        try await waitFor("move rejects pill did not hide when setting turned off") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return framesBox.frames["clove.grid.allReviewed"] != nil
                && framesBox.frames["clove.grid.allReviewed.moveRejects"] == nil
                && framesBox.frames["clove.grid.allReviewed.showAll"] != nil
        }

        // 4. Re-enabling Move Rejects with 0 rejects keeps Move rejects hidden.
        store.update { $0.moveRejectsEnabled = true }
        model.apply(.rating(fourStars), to: photos[1].id)
        await model.drainActions()
        try await waitFor("move rejects pill stayed hidden when 0 rejects exist") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return framesBox.frames["clove.grid.allReviewed"] != nil
                && framesBox.frames["clove.grid.allReviewed.moveRejects"] == nil
                && framesBox.frames["clove.grid.allReviewed.showAll"] != nil
        }

        // 5. Unmarked + metadata filter shows generic empty state with Clear filters instead of all-reviewed.
        model.toggleCameraFilter("NonExistentCamera")
        try await waitFor("generic filtered empty state did not mount") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return framesBox.frames["clove.grid.empty"] != nil
                && framesBox.frames["clove.grid.empty.clearFilters"] != nil
                && framesBox.frames["clove.grid.allReviewed"] == nil
        }

        // 6. Clearing filter back to All restores the full grid.
        model.clearAllFilters()
        try await waitFor("grid did not restore after clearing filters") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return self.findCollectionView(in: window) != nil
                && framesBox.frames["clove.grid.allReviewed"] == nil
                && framesBox.frames["clove.grid.empty"] == nil
        }
    }

    @Test func moveRejectsFlowFromCompletionPreparesConfirmationForRemainingRejects()
        async throws
    {
        let folder = TestLibrary.sampleFolderKey
        let fourStars = try #require(Rating(rawValue: 4))
        let p1 = makePhoto(
            folder: folder, stem: "p1", seconds: 1, marks: PhotoMarks(rating: fourStars))
        let p2 = makePhoto(
            folder: folder, stem: "p2", seconds: 2, marks: PhotoMarks(rating: .rejected))
        let library = TestLibrary(photos: [p1, p2], groups: [])
        let model = BrowsingModel(library: library, similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not finish opening") { !model.isFolderOpening }
        model.setFilter(.unmarked)
        #expect(model.photos.isEmpty)
        #expect(model.rejectedPhotoCount == 1)

        let flow = MoveRejectsFlow(browsing: model)
        await flow.planIfNeeded(
            configuration: RejectMoveConfiguration(settings: SettingsStore.sample.settings))
        guard case .confirming(let plan) = flow.stage else {
            Issue.record("Expected MoveRejectsFlow to enter confirming stage")
            return
        }
        #expect(plan.photoCount == 1)

        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let sheetWindow = UIWindow(windowScene: scene)
        sheetWindow.frame = CGRect(x: 0, y: 0, width: 393, height: 844)
        let sheetHost = UIHostingController(
            rootView: MoveRejectsSheet(flow: flow)
                .environment(SettingsStore.sample)
                .environment(\.cloveTheme, .light))
        sheetWindow.rootViewController = sheetHost
        sheetWindow.makeKeyAndVisible()
        defer {
            sheetWindow.isHidden = true
            sheetWindow.rootViewController = nil
        }
        try await waitFor("MoveRejectsSheet did not render confirmation") {
            sheetHost.view.setNeedsLayout()
            sheetHost.view.layoutIfNeeded()
            return !sheetHost.view.bounds.isEmpty
        }

        await withCheckedContinuation { continuation in
            flow.move(plan) {
                continuation.resume()
            }
        }
        #expect(model.rejectedPhotoCount == 0)
        #expect(model.lastRejectMove != nil)
    }

    @Test func hostedRegularGridScreenShowsAllReviewedWithoutCrashing() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let folder = TestLibrary.sampleFolderKey
        let fourStars = try #require(Rating(rawValue: 4))
        let photos = [
            makePhoto(
                folder: folder, stem: "p1", seconds: 1, marks: PhotoMarks(rating: fourStars)),
            makePhoto(
                folder: folder, stem: "p2", seconds: 2, marks: PhotoMarks(rating: .rejected)),
        ]
        let library = TestLibrary(photos: photos, groups: [])
        let model = BrowsingModel(library: library, similarGroupsEnabled: false)
        model.openFolder()
        try await waitFor("folder did not finish opening") { !model.isFolderOpening }
        model.setFilter(.unmarked)

        let store = SettingsStore.sample
        store.update { $0.moveRejectsEnabled = true }

        let framesBox = AllReviewedFrameStore()
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 1024, height: 768)
        let host = UIHostingController(
            rootView: GridScreen(browsing: model, thumbnails: model.thumbnails)
                .environment(store)
                .environment(\.cloveUserInterfaceIdiom, .pad)
                .environment(\.cloveTheme, .dark)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    framesBox.frames = $0
                })
        host.traitOverrides.horizontalSizeClass = .regular
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitFor("iPad all-reviewed state did not mount") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            return framesBox.frames["clove.grid.allReviewed"] != nil
                && framesBox.frames["clove.grid.allReviewed.moveRejects"] != nil
                && framesBox.frames["clove.grid.allReviewed.showAll"] != nil
        }

        let moveFrame = try #require(framesBox.frames["clove.grid.allReviewed.moveRejects"])
        let showAllFrame = try #require(framesBox.frames["clove.grid.allReviewed.showAll"])
        #expect(moveFrame.maxY <= showAllFrame.minY + 1)
    }

    @Test func allReviewedScalesCleanlyAtAX5AcrossLightAndDarkThemes() async throws {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let summary = GridReviewSummary(
            totalCount: 1240,
            highRatedCount: 312,
            ratedCount: 400,
            labelledOnlyCount: 0,
            rejectedCount: 84,
            moveRejectsEnabled: true)

        for (theme, size) in [
            (CloveTheme.light, CGSize(width: 393, height: 844)),
            (CloveTheme.dark, CGSize(width: 393, height: 844)),
            (CloveTheme.catppuccinMocha, CGSize(width: 393, height: 380)),
        ] {
            let framesBox = AllReviewedFrameStore()
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(origin: .zero, size: size)
            let host = UIHostingController(
                rootView: GridAllReviewedView(
                    summary: summary,
                    onMoveRejects: {},
                    onShowAll: {}
                )
                .environment(\.cloveTheme, theme)
                .environment(\.appLanguage, .english)
                .environment(\.dynamicTypeSize, .accessibility5)
                .onPreferenceChange(HeaderControlFramesPreferenceKey.self) {
                    framesBox.frames = $0
                })
            window.rootViewController = host
            window.makeKeyAndVisible()
            defer {
                window.isHidden = true
                window.rootViewController = nil
            }

            try await waitFor("AX5 all-reviewed view did not lay out for \(theme.id)") {
                host.view.setNeedsLayout()
                host.view.layoutIfNeeded()
                return framesBox.frames["clove.grid.allReviewed"] != nil
                    && framesBox.frames["clove.grid.allReviewed.title"] != nil
                    && framesBox.frames["clove.grid.allReviewed.summary"] != nil
                    && framesBox.frames["clove.grid.allReviewed.moveRejects"] != nil
                    && framesBox.frames["clove.grid.allReviewed.showAll"] != nil
            }

            let titleFrame = try #require(framesBox.frames["clove.grid.allReviewed.title"])
            let summaryFrame = try #require(framesBox.frames["clove.grid.allReviewed.summary"])
            let moveFrame = try #require(framesBox.frames["clove.grid.allReviewed.moveRejects"])
            let showAllFrame = try #require(framesBox.frames["clove.grid.allReviewed.showAll"])

            #expect(titleFrame.width > 0 && titleFrame.height > 0)
            #expect(summaryFrame.width > 0 && summaryFrame.height > 0)
            #expect(moveFrame.width > 0 && moveFrame.height >= 48)
            #expect(showAllFrame.width > 0 && showAllFrame.height >= 48)

            // No horizontal overflow outside the 393pt viewport.
            #expect(titleFrame.minX >= 0 && titleFrame.maxX <= size.width)
            #expect(summaryFrame.minX >= 0 && summaryFrame.maxX <= size.width)
            #expect(moveFrame.minX >= 0 && moveFrame.maxX <= size.width)
            #expect(showAllFrame.minX >= 0 && showAllFrame.maxX <= size.width)

            // Strict vertical stacking without overlap.
            #expect(titleFrame.maxY <= summaryFrame.minY + 1)
            #expect(summaryFrame.maxY <= moveFrame.minY + 1)
            #expect(moveFrame.maxY <= showAllFrame.minY + 1)

            let png = try renderViewPNG(window)
            #expect(!png.isEmpty)
        }
    }

    private func makePhoto(
        folder: FolderIdentity,
        stem: String,
        seconds: TimeInterval,
        marks: PhotoMarks = PhotoMarks(),
        metadata: PhotoFilterMetadata = .empty
    ) -> GridPhoto {
        GridPhoto(
            id: PhotoIdentity(folderID: folder, relativeFolderPath: "", stem: stem),
            fileName: "\(stem).ARW",
            time: .known(
                PhotoTime(
                    captureTime: Date(timeIntervalSince1970: 1_760_000_000 + seconds),
                    hasUTCOffset: true)),
            marks: marks,
            metadata: metadata)
    }

    private func findCollectionView(in view: UIView) -> UICollectionView? {
        if let collection = view as? UICollectionView { return collection }
        for child in view.subviews {
            if let found = findCollectionView(in: child) { return found }
        }
        return nil
    }

    private func renderViewPNG(_ view: UIView) throws -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        var didDraw = false
        let image = UIGraphicsImageRenderer(size: view.bounds.size, format: format).image { _ in
            didDraw = view.drawHierarchy(in: view.bounds, afterScreenUpdates: true)
        }
        #expect(didDraw)
        return try #require(image.pngData())
    }

    private func waitFor(
        _ message: String,
        timeout: Duration = .seconds(3),
        condition: @MainActor () -> Bool
    ) async throws {
        let deadline = ContinuousClock.now + timeout
        while !condition() {
            if ContinuousClock.now >= deadline {
                Issue.record(Comment(rawValue: message))
                throw CancellationError()
            }
            try await Task.sleep(for: .milliseconds(25))
        }
    }
}

@MainActor
private final class AllReviewedFrameStore {
    var frames: [String: CGRect] = [:]
}
