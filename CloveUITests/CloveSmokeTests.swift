import XCTest

/// The smoke test: Clove starts and its main screens open against the in-memory test library.
///
/// It stays short on purpose, with no failure injection and no retries. Everything else that
/// walks the real controls lives in `CloveFlowTests`, which `mise run ui-flows` runs.
final class CloveSmokeTests: XCTestCase {
    @MainActor
    func testMainScreensOpen() {
        let app = XCUIApplication()
        // The in-memory library, so the path needs no folder, fixture or permission.
        app.launchEnvironment["CLOVE_TEST_LIBRARY"] = "1"
        app.launch()
        XCTAssertTrue(
            element(app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear")

        let open = element(app, "clove.entry.openFolder")
        XCTAssertTrue(open.exists, "Entry did not offer the test library")
        open.tap()
        if element(app, "clove.detail").exists { element(app, "clove.nav.back").tap() }
        XCTAssertTrue(
            element(app, "clove.grid").waitForExistence(timeout: 10),
            "The grid did not appear after opening the test library")
        let photo = element(app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(photo.exists, "The grid showed no photos")

        photo.tap()
        let fileName = element(app, "clove.detail.fileName")
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(photo.exists, "Back did not return to the grid")

        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(
            element(app, "clove.settings").exists, "Settings did not open")
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(
            element(app, "clove.grid").exists,
            "Closing Settings did not return to the grid")
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }
}
