import UIKit
import XCTest

extension CloveFlowTests {
    @MainActor
    func testBatchRenameOrdersChecksAndRenamesSelection() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)
        selectRenamePhotos(app)
        let third = element(app, "clove.rename.tile.mmq02680")
        let first = element(app, "clove.rename.tile.mmq02678")
        third.press(forDuration: 0.7, thenDragTo: first)
        XCTAssertEqual(third.value as? String, "Position 1 of 3")
        // Ending a drag above the grid must release the lifted tile and leave it tappable.
        third.press(forDuration: 0.7, thenDragTo: element(app, "clove.rename.cancel"))
        XCTAssertEqual(third.value as? String, "Position 1 of 3")
        capture("rename-order-\(renameDevice)")
        third.tap()
        XCTAssertTrue(element(app, "clove.rename.viewer").exists)
        XCTAssertEqual(element(app, "clove.rename.viewer.name").label, "MMQ02680.ARW")
        let preview = element(app, "clove.rename.viewer.preview")
        preview.doubleTap()
        XCTAssertEqual(preview.value as? String, "Zoomed")
        capture("rename-check-viewer-\(renameDevice)")
        preview.doubleTap()
        XCTAssertEqual(preview.value as? String, "Fit")
        preview.swipeLeft()
        XCTAssertEqual(element(app, "clove.rename.viewer.name").label, "MMQ02678.ARW")
        element(app, "clove.nav.back").tap()
        XCTAssertEqual(third.value as? String, "Position 1 of 3")
        element(app, "clove.rename.next").tap()
        let prefix = app.textFields["clove.rename.prefix"]
        prefix.tap()
        prefix.typeText("Test_")
        app.staticTexts["Rename 3 photos"].tap()
        let confirm = element(app, "clove.rename.confirm")
        XCTAssertTrue(wait(NSPredicate(format: "isEnabled == true"), confirm))
        confirm.tap()
        XCTAssertTrue(element(app, "clove.rename.toast").waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Renamed 3 photos"].exists)
        XCTAssertFalse(element(app, "clove.grid.batch.done").exists)
        let renamed = element(app, "clove.grid.photo.test_001")
        if !renamed.exists { element(app, "clove.grid").collectionViews.firstMatch.swipeDown() }
        renamed.tap()
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "Test_001.ARW")
    }

    @MainActor
    func testBatchRenameShowsReplacementWarningAndProblemRow() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_RENAME_PREVIEW": "1"])
        defer { app.terminate() }
        openLibrary(app)
        selectRenamePhotos(app)
        element(app, "clove.rename.next").tap()
        let prefix = app.textFields["clove.rename.prefix"]
        prefix.tap()
        prefix.typeText("Test_")
        app.staticTexts["Rename 3 photos"].tap()
        XCTAssertTrue(element(app, "clove.rename.replacementCount").waitForExistence(timeout: 5))
        XCTAssertTrue(
            element(app, "clove.rename.preview.mmq02678").label.contains(
                "Replaces a file with this name"))
        let problem = element(app, "clove.rename.preview.mmq02680")
        if !problem.isHittable { app.scrollViews.firstMatch.swipeUp() }
        XCTAssertTrue(problem.label.contains("More than one sidecar matches this photo."))
        let confirm = element(app, "clove.rename.confirm")
        XCTAssertFalse(confirm.isEnabled)
        XCTAssertEqual(confirm.label, "Rename 3 · Replace 1")
        capture("rename-name-warning-and-problem-\(renameDevice)")
    }

    @MainActor
    func testBatchRenamePolishSortRemoveStartInputAndDragSelection() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)
        openSettings(in: app)
        openSettingsCategory("clove.settings.category.browsing", in: app)
        setSimilarGroups(in: app, on: false)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 5))

        // Drag-select across the first three photos from non-selecting state.
        let firstGrid = element(app, "clove.grid.photo.mmq02678")
        let thirdGrid = element(app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(firstGrid.waitForExistence(timeout: 5))
        firstGrid.press(forDuration: 0.7, thenDragTo: thirdGrid)
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")

        // Deselect all keeps empty multi-select active.
        element(app, "clove.grid.selectionOptions").tap()
        app.buttons["Deselect all"].tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        XCTAssertTrue(element(app, "clove.grid.batch.done").exists)

        // Select all then Deselect all, then drag-select 3 photos while already in select mode.
        element(app, "clove.grid.selectionOptions").tap()
        app.buttons["Select all"].tap()
        XCTAssertNotEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        element(app, "clove.grid.selectionOptions").tap()
        app.buttons["Deselect all"].tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "0 selected")

        firstGrid.press(forDuration: 0.7, thenDragTo: thirdGrid)
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")
        XCTAssertTrue(element(app, "clove.grid.batch.rename").isEnabled)
        element(app, "clove.grid.batch.rename").tap()
        XCTAssertTrue(element(app, "clove.rename.order").waitForExistence(timeout: 5))

        // Sort reverse then back to capture time.
        let sortButton = element(app, "clove.rename.sort")
        XCTAssertTrue(sortButton.waitForExistence(timeout: 5))
        sortButton.tap()
        app.buttons["Reverse order"].tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "value == %@", "Position 1 of 3"),
                element(app, "clove.rename.tile.mmq02680"), timeout: 5))

        sortButton.tap()
        app.buttons["Capture time"].tap()
        XCTAssertEqual(
            element(app, "clove.rename.tile.mmq02678").value as? String, "Position 1 of 3")

        // Remove the middle item directly on the Order screen.
        let removeSecond = element(app, "clove.rename.remove.mmq02679")
        XCTAssertTrue(removeSecond.waitForExistence(timeout: 5))
        removeSecond.tap()
        XCTAssertEqual(
            element(app, "clove.rename.tile.mmq02680").value as? String, "Position 2 of 2")

        // Configure prefix, hyphen separator, and direct numeric start input.
        element(app, "clove.rename.next").tap()
        let prefix = app.textFields["clove.rename.prefix"]
        XCTAssertTrue(prefix.waitForExistence(timeout: 5))
        prefix.tap()
        prefix.typeText("Trip")

        let separator = element(app, "clove.rename.separator")
        XCTAssertTrue(separator.exists)
        separator.buttons["-"].tap()

        let startInput = app.textFields["clove.rename.startInput"]
        XCTAssertTrue(startInput.exists)
        startInput.doubleTap()
        startInput.typeText("25")
        app.staticTexts["Rename 2 photos"].tap()

        let previewFirst = element(app, "clove.rename.preview.mmq02678")
        XCTAssertTrue(
            wait(
                NSPredicate(format: "label CONTAINS %@", "Trip-025"),
                previewFirst, timeout: 5))
    }

    @MainActor
    private var renameDevice: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    @MainActor
    private func selectRenamePhotos(_ app: XCUIApplication) {
        openSettings(in: app)
        openSettingsCategory("clove.settings.category.browsing", in: app)
        setSimilarGroups(in: app, on: false)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 5))
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        for stem in ["mmq02678", "mmq02679", "mmq02680"] {
            let photo = element(app, "clove.grid.photo.\(stem)")
            XCTAssertTrue(photo.waitForExistence(timeout: 5))
            photo.tap()
        }
        element(app, "clove.grid.batch.rename").tap()
        XCTAssertTrue(element(app, "clove.rename.order").exists)
    }
}
