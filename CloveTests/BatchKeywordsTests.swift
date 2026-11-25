import CloveCore
import Foundation
import SwiftUI
import Testing
import UIKit

@testable import Clove

@MainActor
struct BatchKeywordsTests {
    @Test func parseSplitsCommasFullwidthCommasNewlinesAndDeduplicates() {
        let parsed = BatchKeywords.parse(
            "  Harbour , blue hour，sunset\nHarbour\r\n  ， Dawn , blue hour  ")
        #expect(parsed == ["Harbour", "blue hour", "sunset", "Dawn"])
        #expect(BatchKeywords.parse("   , ，\n  ").isEmpty)
    }

    @Test func commonAndMixedKeywordsPartitionTargetKeywordsCleanly() {
        let library = ControlledPhotoLibrary(stems: ["a", "b", "c"])
        let targets = [
            GridPhoto(
                id: library.identity("a"), fileName: "a.ARW", time: .unavailable,
                marks: PhotoMarks(keywords: ["Dawn", "Harbour", "Portrait"])),
            GridPhoto(
                id: library.identity("b"), fileName: "b.ARW", time: .unavailable,
                marks: PhotoMarks(keywords: ["Harbour", "Portrait", "Street"])),
        ]

        #expect(BatchKeywords.commonKeywords(in: targets) == ["Harbour", "Portrait"])
        #expect(BatchKeywords.mixedKeywords(in: targets) == ["Dawn", "Street"])
        #expect(BatchKeywords.mixedKeywords(in: Array(targets.prefix(1))).isEmpty)
    }

    @Test func suggestionsRankByFrequencyThenAlphabeticalAndExcludeCommonOrPending() {
        let library = ControlledPhotoLibrary(stems: ["a", "b", "c", "d"])
        let photos = [
            GridPhoto(
                id: library.identity("a"), fileName: "a.ARW", time: .unavailable,
                marks: PhotoMarks(keywords: ["Harbour", "Dawn"])),
            GridPhoto(
                id: library.identity("b"), fileName: "b.ARW", time: .unavailable,
                marks: PhotoMarks(keywords: ["Harbour", "Sunset", "Alpha"])),
            GridPhoto(
                id: library.identity("c"), fileName: "c.ARW", time: .unavailable,
                marks: PhotoMarks(keywords: ["Sunset", "Beta"])),
            GridPhoto(
                id: library.identity("d"), fileName: "d.ARW", time: .unavailable,
                marks: PhotoMarks(keywords: ["Alpha"])),
        ]
        let targets = [photos[0], photos[3]]
        let ranked = BatchKeywords.suggestions(
            in: photos, targets: targets, excluding: ["Sunset"])
        // Alpha (2), Harbour (2), Beta (1), Dawn (1); Sunset excluded as pending.
        #expect(ranked == ["Alpha", "Harbour", "Beta", "Dawn"])
    }

    @Test func batchAddAndRemovePreserveExistingKeywordsAndUndoInSingleStep() async {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["a", "b", "c"])
        let a = library.identity("a")
        let b = library.identity("b")
        let c = library.identity("c")
        library.photos[0].marks = PhotoMarks(keywords: ["Existing"])
        library.photos[1].marks = PhotoMarks(keywords: ["Existing", "Unique"])

        let model = BrowsingModel(library: library)
        model.openFolder()
        model.toggleSelection(a)
        model.toggleSelection(b)

        model.applyBatch(.addKeywords(["Harbour", "Dawn"]), settings: AppSettings())
        #expect(model.shownMarks(for: a).keywords == ["Existing", "Harbour", "Dawn"])
        #expect(model.shownMarks(for: b).keywords == ["Existing", "Unique", "Harbour", "Dawn"])
        #expect(model.shownMarks(for: c).keywords.isEmpty)
        #expect(model.canUndoMark)

        // Removing a common keyword leaves unique and remaining keywords intact.
        model.applyBatch(.removeKeywords(["Harbour"]), settings: AppSettings())
        #expect(model.shownMarks(for: a).keywords == ["Existing", "Dawn"])
        #expect(model.shownMarks(for: b).keywords == ["Existing", "Unique", "Dawn"])

        // Single-step Undo restores the state prior to removing Harbour.
        model.undoLastMark()
        #expect(model.shownMarks(for: a).keywords == ["Existing", "Harbour", "Dawn"])
        #expect(model.shownMarks(for: b).keywords == ["Existing", "Unique", "Harbour", "Dawn"])
        #expect(!model.canUndoMark)

        await model.drainActions()
        #expect(
            library.photos.first { $0.id == a }?.marks.keywords == ["Existing", "Harbour", "Dawn"])
        #expect(
            library.photos.first { $0.id == b }?.marks.keywords
                == ["Existing", "Unique", "Harbour", "Dawn"])
    }

    @Test func filteredBatchKeywordEditLeavesHiddenSelectedPhotosUntouched() async {
        let library = ControlledPhotoLibrary(rejected: ["b"], stems: ["a", "b"])
        let a = library.identity("a")
        let b = library.identity("b")

        let model = BrowsingModel(library: library)
        model.openFolder()
        model.toggleSelection(a)
        model.toggleSelection(b)
        model.setFilter(.unmarked)

        #expect(model.batchTargets.map(\.id) == [a])
        #expect(model.hiddenSelectedCount == 1)

        model.applyBatch(.addKeywords(["VisibleOnly"]), settings: AppSettings())
        await model.drainActions()

        #expect(model.shownMarks(for: a).keywords == ["VisibleOnly"])
        #expect(model.shownMarks(for: b).keywords.isEmpty)
        #expect(library.photos.first { $0.id == b }?.marks.keywords.isEmpty == true)
    }

    @Test func batchKeywordWriteFailureShowsToastAndRereadsFailedPhoto() async {
        let library = ControlledPhotoLibrary(rejected: [], stems: ["a", "b"])
        let a = library.identity("a")
        let b = library.identity("b")
        library.failNext.insert(b)
        library.rereadValues[b] = PhotoMarks(keywords: ["Persisted"])

        let model = BrowsingModel(library: library)
        model.openFolder()
        model.toggleSelection(a)
        model.toggleSelection(b)

        model.applyBatch(.addKeywords(["Harbour"]), settings: AppSettings())
        await model.drainActions()

        #expect(model.failureToastMessage == BrowsingModel.saveFailureToastMessage)
        #expect(library.rereads.contains(b))
        #expect(model.shownMarks(for: a).keywords == ["Harbour"])
        #expect(model.shownMarks(for: b).keywords == ["Persisted"])
    }

    @Test func infoSheetFormatsKeywordsAndKeywordOnlyMarksSummary() throws {
        let keywordOnlySingle = PhotoMarks(keywords: ["Dawn"])
        let keywordOnlyMultiple = PhotoMarks(keywords: ["Harbour", "Dawn"])
        let ratedAndKeywords = PhotoMarks(
            rating: try #require(Rating(rawValue: 4)),
            label: ColourLabel(colour: .blue),
            keywords: ["Harbour", "Dawn"])
        let unmarked = PhotoMarks()

        #expect(PhotoInformationSheet.keywordsText(for: unmarked) == nil)
        #expect(PhotoInformationSheet.keywordsText(for: keywordOnlyMultiple) == "Harbour, Dawn")

        let singleSummary = PhotoInformationSheet.marksSummary(
            for: keywordOnlySingle, language: .english)
        #expect(singleSummary.text == "1 keyword")
        #expect(singleSummary.isNeutral)

        let multiSummary = PhotoInformationSheet.marksSummary(
            for: keywordOnlyMultiple, language: .english)
        #expect(multiSummary.text == "2 keywords")
        #expect(multiSummary.isNeutral)

        let hansSummary = PhotoInformationSheet.marksSummary(
            for: keywordOnlyMultiple, language: .simplifiedChinese)
        #expect(hansSummary.text == "2 个关键词")
        #expect(hansSummary.isNeutral)

        let ratedSummary = PhotoInformationSheet.marksSummary(
            for: ratedAndKeywords, language: .english)
        #expect(ratedSummary.text == "★★★★ · Blue")
        #expect(!ratedSummary.isNeutral)

        let unmarkedSummary = PhotoInformationSheet.marksSummary(
            for: unmarked, language: .english)
        #expect(unmarkedSummary.text == "Unmarked")
        #expect(unmarkedSummary.isNeutral)
    }

    @Test func batchKeywordsSheetStagesAndCommitsInConfirmModeWithoutPrematureWrites() async throws
    {
        let scene = try #require(
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let library = ControlledPhotoLibrary(rejected: [], stems: ["a", "b", "c"])
        let a = library.identity("a")
        let b = library.identity("b")
        let c = library.identity("c")
        library.photos[2].marks = PhotoMarks(keywords: ["Harbour", "Dawn"])

        let browsing = BrowsingModel(library: library)
        browsing.openFolder()
        browsing.toggleSelection(a)
        browsing.toggleSelection(b)
        #expect(browsing.batchTargets.count == 2)

        let storage = SampleSettingsStorage()
        let store = SettingsStore(
            persistence: SettingsPersistence(storage: storage),
            rememberedAdvanceStorage: storage,
            physicalMemory: 8 * 1024 * 1024 * 1024)
        store.update { $0.confirmBatchActions = true }

        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 393, height: 700)
        let host = UIHostingController(
            rootView: BatchKeywordsSheet(browsing: browsing)
                .environment(store)
                .environment(\.cloveTheme, .light)
                .environment(\.appLanguage, .english))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer {
            window.isHidden = true
            window.rootViewController = nil
        }

        try await waitForCondition("BatchKeywordsSheet mounted") {
            host.view.setNeedsLayout()
            host.view.layoutIfNeeded()
            guard host.view.bounds.size.width > 0, !host.children.isEmpty else { return false }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            return image.size.width > 0 && image.size.height > 0
        }

        #expect(
            BatchKeywordsSheet.navigationTitle(isStagedConfirmation: true, language: .english)
                == "Add Keywords")
        #expect(
            BatchKeywordsSheet.navigationTitle(isStagedConfirmation: false, language: .english)
                == "Keywords")
        #expect(
            BatchKeywordsSheet.confirmTitle(
                targetCount: browsing.batchTargets.count, language: .english) == "Add to 2 Photos")

        // Staging and unstaging mutate in-memory state with zero writes until confirmed.
        var staged = BatchKeywordsSheet.stagedAfterAdding(["Harbour", "Dawn"], to: [])
        #expect(staged == ["Harbour", "Dawn"])
        staged = BatchKeywordsSheet.stagedAfterAdding(["Harbour"], to: staged)
        #expect(staged == ["Harbour", "Dawn"])
        staged.removeAll { $0 == "Dawn" }
        #expect(staged == ["Harbour"])
        await browsing.drainActions()
        #expect(browsing.shownMarks(for: a).keywords.isEmpty)
        #expect(browsing.shownMarks(for: b).keywords.isEmpty)
        #expect(library.writes.isEmpty)

        // Confirming commits staged (+ entered, deduplicated) keywords in one undoable batch.
        let committed = BatchKeywordsSheet.combinedStagedKeywords(
            staged, entered: ["Harbour", "Coast"])
        #expect(committed == ["Harbour", "Coast"])
        browsing.applyBatch(.addKeywords(committed), settings: store.settings)
        await browsing.drainActions()

        #expect(browsing.shownMarks(for: a).keywords == ["Harbour", "Coast"])
        #expect(browsing.shownMarks(for: b).keywords == ["Harbour", "Coast"])
        #expect(browsing.shownMarks(for: c).keywords == ["Harbour", "Dawn"])
        #expect(browsing.canUndoMark)

        browsing.undoLastMark()
        await browsing.drainActions()
        #expect(browsing.shownMarks(for: a).keywords.isEmpty)
        #expect(browsing.shownMarks(for: b).keywords.isEmpty)
    }

    private func waitForCondition(
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
