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
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Position 1 of 3"), third))
        // Ending a drag above the grid must release the lifted tile and leave it tappable.
        third.press(forDuration: 0.7, thenDragTo: element(app, "clove.rename.cancel"))
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Position 1 of 3"), third))
        capture("rename-order-\(renameDevice)")
        third.tap()
        XCTAssertTrue(element(app, "clove.rename.viewer").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.rename.viewer.name").label, "MMQ02680.ARW")
        let preview = element(app, "clove.rename.viewer.preview")
        preview.doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Zoomed"), preview))
        capture("rename-check-viewer-\(renameDevice)")
        preview.doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Fit"), preview))
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", element(app, "clove.rename.viewer.name")))
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertEqual(third.value as? String, "Position 1 of 3")
        element(app, "clove.rename.next").tap()
        let prefix = app.textFields["clove.rename.prefix"]
        XCTAssertTrue(prefix.waitForExistence(timeout: 5))
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
        XCTAssertTrue(renamed.waitForExistence(timeout: 5))
        renamed.tap()
        XCTAssertTrue(waitForLabel("Test_001.ARW", element(app, "clove.detail.fileName")))
    }

    @MainActor
    func testBatchRenameShowsReplacementWarningAndProblemRow() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_RENAME_PREVIEW": "1"])
        defer { app.terminate() }
        openLibrary(app)
        selectRenamePhotos(app)
        element(app, "clove.rename.next").tap()
        let prefix = app.textFields["clove.rename.prefix"]
        XCTAssertTrue(prefix.waitForExistence(timeout: 5))
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
        XCTAssertFalse(element(app, "clove.rename.confirm").isEnabled)
        XCTAssertEqual(element(app, "clove.rename.confirm").label, "Rename 3 · Replace 1")
        capture("rename-name-warning-and-problem-\(renameDevice)")
    }

    @MainActor
    private var renameDevice: String {
        UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    }

    @MainActor
    private func selectRenamePhotos(_ app: XCUIApplication) {
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        for stem in ["mmq02678", "mmq02679", "mmq02680"] {
            let photo = element(app, "clove.grid.photo.\(stem)")
            XCTAssertTrue(photo.waitForExistence(timeout: 5))
            photo.tap()
        }
        element(app, "clove.grid.batch.rename").tap()
        XCTAssertTrue(element(app, "clove.rename.order").waitForExistence(timeout: 5))
    }
}
