import UIKit
import XCTest

extension CloveFlowTests {
    @MainActor
    func testMoreFiltersOpensFromFilterMenuAndAppliesFilter() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Header Filter menu and More filters sheet are compact-width phone behavior")
        let app = launchSample(["CLOVE_TEST_LIBRARY_METADATA_SAMPLES": "1"])
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
        openLibrary(app)

        let filterButton = element(app, "clove.grid.filter")
        let moreFilters = filterMenuItem(app, "More filters")
        let sheet = element(app, "clove.grid.metadataFilter.sheet")
        let doneButton = element(app, "clove.grid.metadataFilter.done")

        // 1. Choosing a regular filter dismisses the menu without opening MetadataFilterSheet.
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        if let value = filterButton.value as? String, !value.isEmpty {
            XCTAssertEqual(value, "Off")
        }
        filterButton.tap()
        let unmarked = filterMenuItem(app, "Unmarked")
        XCTAssertTrue(unmarked.waitForExistence(timeout: 5))
        unmarked.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), unmarked))
        XCTAssertFalse(sheet.exists)
        if let value = filterButton.value as? String, !value.isEmpty {
            XCTAssertEqual(value, "On")
        }
        filterButton.tap()
        let allFilter = filterMenuItem(app, "All")
        XCTAssertTrue(allFilter.waitForExistence(timeout: 5))
        XCTAssertTrue(unmarked.isSelected)
        allFilter.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), allFilter))
        if let value = filterButton.value as? String, !value.isEmpty {
            XCTAssertEqual(value, "Off")
        }

        // 2. Rating >= palette selects a floor and tapping the active floor clears back to All.
        filterButton.tap()
        let threePlus = filterMenuItem(app, "★3+")
        XCTAssertTrue(threePlus.waitForExistence(timeout: 5))
        threePlus.tap()
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == true"), threePlus))
        XCTAssertTrue(waitForLabel("Rating ≥ 3 · 1", element(app, "clove.grid.subtitle")))
        threePlus.tap()
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == false"), threePlus))
        XCTAssertTrue(waitForLabel("36 photos", element(app, "clove.grid.subtitle")))

        // 3. Label palette selects a color label and tapping the active label clears back to All.
        let greenLabel = filterMenuItem(app, "Green")
        XCTAssertTrue(greenLabel.waitForExistence(timeout: 5))
        greenLabel.tap()
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == true"), greenLabel))
        XCTAssertTrue(waitForLabel("Green · 1", element(app, "clove.grid.subtitle")))
        greenLabel.tap()
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == false"), greenLabel))
        XCTAssertTrue(waitForLabel("36 photos", element(app, "clove.grid.subtitle")))

        // 4. Tap "More filters" inside the open menu to present MetadataFilterSheet directly.
        XCTAssertTrue(moreFilters.waitForExistence(timeout: 5))
        moreFilters.tap()

        // MetadataFilterSheet must present and be interactive after the menu dismisses.
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "MetadataFilterSheet did not appear after tapping More filters in the Filter menu")
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

        // Re-opening Filter menu shows the active metadata filter count in "More filters".
        filterButton.tap()
        let activeMoreFilters = filterMenuItem(app, "More filters")
        XCTAssertTrue(activeMoreFilters.waitForExistence(timeout: 5))
        XCTAssertTrue(activeMoreFilters.label.contains("1 filter"))
        activeMoreFilters.tap()
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        doneButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))

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

        // 5. Also verify Filter menu -> More filters while in Select mode.
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        XCTAssertTrue(element(app, "clove.grid.batch.done").waitForExistence(timeout: 5))
        filterButton.tap()
        XCTAssertTrue(moreFilters.waitForExistence(timeout: 5))
        moreFilters.tap()
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "MetadataFilterSheet did not appear from Filter menu in Select mode")
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

        // 6. Verify Filter menu -> More filters in phone landscape as well.
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), filterButton, timeout: 5))
        filterButton.tap()
        XCTAssertTrue(moreFilters.waitForExistence(timeout: 5))
        moreFilters.tap()
        XCTAssertTrue(
            sheet.waitForExistence(timeout: 5),
            "MetadataFilterSheet did not appear from Filter menu in landscape")
        XCTAssertTrue(doneButton.waitForExistence(timeout: 5))
        doneButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))
    }
}
