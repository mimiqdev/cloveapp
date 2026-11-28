import UIKit
import XCTest

extension CloveFlowTests {
    @MainActor
    func testMoreFiltersOpensFromFilterPopoverAndAppliesFilter() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Header Filter popover and More filters sheet are compact-width phone behavior")
        let app = launchSample(["CLOVE_TEST_LIBRARY_METADATA_SAMPLES": "1"])
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
        openLibrary(app)

        let filterButton = element(app, "clove.grid.filter")
        let moreFilters = element(app, "clove.grid.filter.more")
        let sheet = element(app, "clove.grid.metadataFilter.sheet")
        let doneButton = element(app, "clove.grid.metadataFilter.done")

        // 1. Choosing a regular filter dismisses the popover without opening MetadataFilterSheet.
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()
        let unmarked = element(app, "clove.grid.filter.unmarked")
        XCTAssertTrue(unmarked.waitForExistence(timeout: 5))
        unmarked.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), unmarked))
        XCTAssertFalse(sheet.exists)
        filterButton.tap()
        let allFilter = element(app, "clove.grid.filter.all")
        XCTAssertTrue(allFilter.waitForExistence(timeout: 5))
        allFilter.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), allFilter))

        // 2. Open Filter popover and tap "More filters".
        filterButton.tap()
        XCTAssertTrue(moreFilters.waitForExistence(timeout: 5))
        moreFilters.tap()

        // MetadataFilterSheet must present and be interactive after the popover dismisses.
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "MetadataFilterSheet did not appear after tapping More filters in the Filter popover")
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        XCTAssertTrue(doneButton.isHittable)

        // Apply a camera filter inside the sheet and verify live match summary updates.
        let cameraOption = element(app, "clove.grid.metadataFilter.camera.ILCE-1M2")
        XCTAssertTrue(cameraOption.waitForExistence(timeout: 5))
        cameraOption.tap()
        let summary = element(app, "clove.grid.metadataFilter.summary")
        XCTAssertTrue(waitForLabel("Showing 18 of 36", summary))

        // Dismiss the sheet and verify ActiveMetadataFilterBar + chip appear on Grid.
        doneButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))

        let filterBar = element(app, "clove.grid.metadataFilter.bar")
        XCTAssertTrue(filterBar.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.grid.metadataFilter.active.camera").exists)

        // Tapping the ActiveMetadataFilterBar edit button re-opens MetadataFilterSheet directly.
        let barEdit = element(app, "clove.grid.metadataFilter.bar.edit")
        XCTAssertTrue(barEdit.waitForExistence(timeout: 5))
        barEdit.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))

        // Clear via the sheet's Clear button and dismiss cleanly.
        let sheetClear = element(app, "clove.grid.metadataFilter.clear")
        XCTAssertTrue(sheetClear.waitForExistence(timeout: 5))
        sheetClear.tap()
        XCTAssertTrue(waitForLabel("Showing 36 of 36", summary))
        doneButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), filterBar))

        // 3. Also verify Filter popover -> More filters while in Select mode.
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        XCTAssertTrue(element(app, "clove.grid.batch.done").waitForExistence(timeout: 5))
        filterButton.tap()
        XCTAssertTrue(moreFilters.waitForExistence(timeout: 5))
        moreFilters.tap()
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "MetadataFilterSheet did not appear from Filter popover in Select mode")
        let keywordOption = element(app, "clove.grid.metadataFilter.keyword.Coast")
        let filterList = sheet.collectionViews.firstMatch
        for _ in 0..<5 {
            if keywordOption.exists && keywordOption.isHittable { break }
            if filterList.exists {
                filterList.swipeUp()
            } else {
                sheet.swipeUp()
            }
        }
        XCTAssertTrue(keywordOption.waitForExistence(timeout: 5))
        keywordOption.tap()
        doneButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))
        XCTAssertTrue(
            element(app, "clove.grid.metadataFilter.active.keyword").waitForExistence(timeout: 5))

        // Clear via ActiveMetadataFilterBar Clear button and exit Select mode.
        element(app, "clove.grid.metadataFilter.bar.clear").tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), filterBar))
        element(app, "clove.grid.batch.done").tap()

        // 4. Verify Filter popover -> More filters in phone landscape as well.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), filterButton, timeout: 5))
        filterButton.tap()
        XCTAssertTrue(moreFilters.waitForExistence(timeout: 5))
        moreFilters.tap()
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "MetadataFilterSheet did not appear from Filter popover in landscape")
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))
    }
}
