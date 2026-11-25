import CloveCore
import Foundation
import Testing

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
}
