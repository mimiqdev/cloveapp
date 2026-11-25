import UIKit
import XCTest

extension CloveFlowTests {
    @MainActor
    func testBatchRenameOrdersChecksAndRenamesSelection() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)
        selectRenamePhotos(app)
        XCTAssertEqual(
            element(app, "clove.rename.order.footer").label,
            "Cancel discards changes to the order.")
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
        let subtitle = element(app, "clove.rename.subtitle")
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
        XCTAssertEqual(subtitle.label, "Preview names before applying changes.")
        XCTAssertEqual(
            element(app, "clove.rename.previewNote").label,
            "Replacements are flagged in the preview.")
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
        let subtitle = element(app, "clove.rename.subtitle")
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
        XCTAssertEqual(subtitle.label, "Preview names before applying changes.")
        XCTAssertEqual(
            element(app, "clove.rename.previewNote").label,
            "Replacements are flagged in the preview.")
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

        // Select All toggles to Deselect All, and Deselect All keeps empty multi-select active with disabled batch controls.
        let selectAllButton = element(app, "clove.grid.selectAll")
        XCTAssertTrue(selectAllButton.waitForExistence(timeout: 5))
        XCTAssertEqual(selectAllButton.label, "Select All")
        selectAllButton.tap()
        XCTAssertNotEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        XCTAssertTrue(waitForLabel("Deselect All", selectAllButton))

        selectAllButton.tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        XCTAssertTrue(waitForLabel("Select All", selectAllButton))
        XCTAssertTrue(element(app, "clove.grid.batch.done").exists)
        XCTAssertTrue(element(app, "clove.grid.batch").exists)
        XCTAssertTrue(element(app, "clove.grid.batch.bar").exists)
        XCTAssertFalse(element(app, "clove.grid.batch.reject").isEnabled)
        XCTAssertFalse(element(app, "clove.grid.batch.rating").isEnabled)
        XCTAssertFalse(element(app, "clove.grid.batch.label").isEnabled)
        XCTAssertFalse(element(app, "clove.grid.batch.actions").isEnabled)

        firstGrid.press(forDuration: 0.7, thenDragTo: thirdGrid)
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")
        let actionsButton = element(app, "clove.grid.batch.actions")
        XCTAssertTrue(actionsButton.isEnabled)
        actionsButton.tap()
        let renameItem = element(app, "clove.grid.batch.rename")
        XCTAssertTrue(renameItem.waitForExistence(timeout: 5))
        renameItem.tap()
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
        let subtitle = element(app, "clove.rename.subtitle")
        XCTAssertTrue(subtitle.waitForExistence(timeout: 5))
        XCTAssertEqual(subtitle.label, "Preview names before applying changes.")
        XCTAssertEqual(
            element(app, "clove.rename.previewNote").label,
            "Replacements are flagged in the preview.")
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
    func testSelectionToolbarFilterHiddenCountAndRenameCancelPreservesState() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer {
            XCUIDevice.shared.orientation = .portrait
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
        openLibrary(app)
        openSettings(in: app)
        openSettingsCategory("clove.settings.category.browsing", in: app)
        setSimilarGroups(in: app, on: false)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 5))

        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        XCTAssertFalse(element(app, "clove.grid.batch.actions").isEnabled)
        XCTAssertTrue(element(app, "clove.grid.selectAll").exists)
        XCTAssertTrue(element(app, "clove.grid.batch.done").exists)

        // Two-capsule batch bar geometry: Marking capsule (168x48) + 8pt gap + Actions capsule (110x48).
        let markingCapsule = element(app, "clove.grid.batch.bar")
        let actionsCapsule = element(app, "clove.grid.batch.actions")
        XCTAssertTrue(markingCapsule.waitForExistence(timeout: 5))
        XCTAssertTrue(actionsCapsule.waitForExistence(timeout: 5))
        XCTAssertEqual(markingCapsule.frame.width, 168, accuracy: 2)
        XCTAssertEqual(actionsCapsule.frame.width, 110, accuracy: 2)
        XCTAssertEqual(actionsCapsule.frame.minX - markingCapsule.frame.maxX, 8, accuracy: 2)

        for stem in ["mmq02678", "mmq02679"] {
            let photo = element(app, "clove.grid.photo.\(stem)")
            XCTAssertTrue(photo.waitForExistence(timeout: 5))
            photo.tap()
        }
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        if UIDevice.current.userInterfaceIdiom == .phone {
            XCTAssertFalse(element(app, "clove.grid.batch.compare").exists)
            XCUIDevice.shared.orientation = .landscapeLeft
            let compareCapsule = element(app, "clove.grid.batch.compare")
            XCTAssertTrue(compareCapsule.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(
                compareCapsule.frame.minX, element(app, "clove.grid.batch.actions").frame.maxX - 1)
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(
                wait(
                    NSPredicate(format: "exists == false"),
                    element(app, "clove.grid.batch.compare"), timeout: 5))
        }

        let thirdPhoto = element(app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(thirdPhoto.waitForExistence(timeout: 5))
        thirdPhoto.tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")
        XCTAssertFalse(element(app, "clove.grid.batch.compare").exists)

        // Normalize all three to 4 stars, then reject only the first while keeping all three selected.
        element(app, "clove.grid.batch.rating").tap()
        XCTAssertTrue(element(app, "clove.grid.batch.stars").waitForExistence(timeout: 5))
        element(app, "clove.grid.batch.stars.4").tap()
        element(app, "clove.grid.photo.mmq02679").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
        element(app, "clove.grid.batch.reject").tap()
        element(app, "clove.grid.photo.mmq02679").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")

        if UIDevice.current.userInterfaceIdiom == .phone {
            let filterButton = element(app, "clove.grid.filter")
            XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
            filterButton.tap()
            element(app, "clove.grid.filter.rejected").tap()

            XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
            let hiddenCount = element(app, "clove.grid.batch.hiddenCount")
            XCTAssertTrue(hiddenCount.waitForExistence(timeout: 5))
            XCTAssertEqual(hiddenCount.label, "2 hidden by filter")

            // Actions menu order: Rename… -> Save to Photos… -> Add Keywords…
            // Actions -> Rename… scopes strictly to visible targets and Cancel preserves filter & selection.
            element(app, "clove.grid.batch.actions").tap()
            let renameItem = element(app, "clove.grid.batch.rename")
            let saveItem = element(app, "clove.grid.batch.saveToPhotos")
            let keywordsItem = element(app, "clove.grid.batch.keywords")
            XCTAssertTrue(renameItem.waitForExistence(timeout: 5))
            XCTAssertTrue(saveItem.waitForExistence(timeout: 5))
            XCTAssertTrue(keywordsItem.waitForExistence(timeout: 5))
            XCTAssertLessThan(renameItem.frame.minY, saveItem.frame.minY)
            XCTAssertLessThan(saveItem.frame.minY, keywordsItem.frame.minY)

            renameItem.tap()
            XCTAssertTrue(element(app, "clove.rename.order").waitForExistence(timeout: 5))
            XCTAssertTrue(app.staticTexts["Order 1 photo"].exists)
            XCTAssertTrue(element(app, "clove.rename.tile.mmq02678").exists)
            XCTAssertFalse(element(app, "clove.rename.tile.mmq02679").exists)

            element(app, "clove.rename.cancel").tap()
            XCTAssertTrue(element(app, "clove.grid.batch").waitForExistence(timeout: 5))
            XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
            XCTAssertEqual(element(app, "clove.grid.batch.hiddenCount").label, "2 hidden by filter")

            // Switching filter back to All restores all 3 selected photos.
            filterButton.tap()
            element(app, "clove.grid.filter.all").tap()
            XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")
            XCTAssertFalse(element(app, "clove.grid.batch.hiddenCount").exists)
        }
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
        let actions = element(app, "clove.grid.batch.actions")
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.isEnabled)
        actions.tap()
        let renameItem = element(app, "clove.grid.batch.rename")
        XCTAssertTrue(renameItem.waitForExistence(timeout: 5))
        renameItem.tap()
        XCTAssertTrue(element(app, "clove.rename.order").waitForExistence(timeout: 5))
    }
}
