import XCTest

/// The Clove UI smoke test: the grid's overlays, its filter, and U1's path from entry to
/// settings, all against the in-memory test library (PRD Grid, P0-03, P0-13).
final class CloveUITests: XCTestCase {
    @MainActor
    func testBrowsingFlowFromEntryToSettings() {
        let app = XCUIApplication()
        // The in-memory library, so the path needs no folder, fixture or permission.
        app.launchEnvironment["CLOVE_TEST_LIBRARY"] = "1"
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear"
        )

        openTestLibrary(in: app)
        checkGridOverlays(in: app)
        showOnlyRejectedThenAll(in: app)
        openFirstPhoto(in: app)
        markThePhoto(in: app)
        returnToGrid(in: app)
        openGroup(in: app)
        openSettings(in: app)
    }

    /// Entry opens the test library and the grid appears.
    @MainActor
    private func openTestLibrary(in app: XCUIApplication) {
        let open = element(in: app, "clove.entry.openFolder")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Entry did not offer the test library")
        open.tap()
        XCTAssertTrue(
            element(in: app, "clove.grid").waitForExistence(timeout: 10),
            "The grid did not appear after opening the folder"
        )
    }

    /// Cells read their marks: the rating and colour dot, the Reject flag and the companion badge
    /// (PRD Grid, P0-03).
    @MainActor
    private func checkGridOverlays(in app: XCUIApplication) {
        let rated = element(in: app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(rated.waitForExistence(timeout: 10), "The grid did not show its first cell")
        XCTAssertTrue(rated.label.contains("MMQ02678.ARW"), "The cell lost its file name")
        XCTAssertTrue(
            rated.label.contains("5 stars"), "The cell lost its rating: \(rated.label)")
        XCTAssertTrue(rated.label.contains("Red"), "The cell lost its colour dot: \(rated.label)")

        let rejected = element(in: app, "clove.grid.photo.mmq02679")
        XCTAssertTrue(rejected.exists, "The grid did not show the second cell")
        XCTAssertTrue(
            rejected.label.contains("Rejected"), "The cell lost its Reject flag: \(rejected.label)")

        let companion = element(in: app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(companion.exists, "The grid did not show the third cell")
        XCTAssertTrue(
            companion.label.contains("JPEG companion"),
            "The cell lost its companion badge: \(companion.label)")
    }

    /// The Rejected filter shows only rejected photos, and All brings every photo back
    /// (PRD P0-03).
    @MainActor
    private func showOnlyRejectedThenAll(in app: XCUIApplication) {
        selectMenuItem(in: app, "clove.grid.filter", item: "clove.grid.filter.rejected")
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02679").waitForExistence(timeout: 10),
            "The Rejected filter did not show a rejected photo"
        )
        XCTAssertFalse(
            element(in: app, "clove.grid.photo.mmq02678").exists,
            "The Rejected filter showed an unrejected photo"
        )

        selectMenuItem(in: app, "clove.grid.filter", item: "clove.grid.filter.all")
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02678").waitForExistence(timeout: 10),
            "The All filter did not bring the photos back"
        )
    }

    /// Taps a menu control, then its item (PRD P0-03).
    @MainActor
    private func selectMenuItem(
        in app: XCUIApplication, _ control: String, item: String
    ) {
        let menu = element(in: app, control)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "The grid did not show \(control)")
        menu.tap()
        let choice = app.buttons[item]
        XCTAssertTrue(
            choice.waitForExistence(timeout: 10), "The menu did not offer \(item)")
        choice.tap()
    }

    /// The grid opens the first photo's detail, which shows its file name and saved marks.
    ///
    /// Identifiers carry the photo's identity stem, which is folded to lower case, so the first
    /// sample photo is `mmq02678`.
    @MainActor
    private func openFirstPhoto(in app: XCUIApplication) {
        let first = element(in: app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The grid did not show the first photo")
        first.tap()

        let fileName = element(in: app, "clove.detail.fileName")
        XCTAssertTrue(
            fileName.waitForExistence(timeout: 10), "The detail view did not show the file name")
        XCTAssertEqual(fileName.label, "MMQ02678.ARW")

        let marks = element(in: app, "clove.detail.marks")
        XCTAssertTrue(marks.exists, "The detail view did not show the photo's marks")
        XCTAssertTrue(
            marks.label.contains("5 stars"),
            "The detail view did not show the saved rating: \(marks.label)"
        )
    }

    /// A rating applied in detail writes through the seam and the detail shows the confirmed save
    /// state (PRD P0-05, P0-08).
    @MainActor
    private func markThePhoto(in app: XCUIApplication) {
        let saveState = element(in: app, "clove.detail.saveState")
        XCTAssertTrue(saveState.waitForExistence(timeout: 10), "The detail view had no save state")
        XCTAssertEqual(saveState.label, "No change yet")

        let fourStars = element(in: app, "clove.detail.rate.4")
        XCTAssertTrue(
            fourStars.waitForExistence(timeout: 10), "The detail view had no rating buttons")
        fourStars.tap()

        let saved = expectation(
            for: NSPredicate(format: "label == %@", "Saved"), evaluatedWith: saveState)
        wait(for: [saved], timeout: 10)

        let marks = element(in: app, "clove.detail.marks")
        XCTAssertTrue(
            marks.label.contains("4 stars"),
            "The detail view did not show the new rating: \(marks.label)")
    }

    /// Back returns from detail to the grid, and the grid shows the saved rating the update path
    /// carried back through the library (PRD P0-03, P0-08).
    @MainActor
    private func returnToGrid(in app: XCUIApplication) {
        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The detail view had no back button")
        back.tap()
        let row = element(in: app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Back did not return to the grid")
        XCTAssertTrue(
            row.label.contains("4 stars"),
            "The grid did not show the saved rating: \(row.label)"
        )
    }

    /// The grid opens a group's view from its count tag (PRD Grid, P0-11).
    @MainActor
    private func openGroup(in app: XCUIApplication) {
        let group = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(group.waitForExistence(timeout: 10), "The grid did not offer a similar group")
        XCTAssertTrue(group.isHittable, "The group's count tag was not tappable")
        group.tap()
        XCTAssertTrue(
            element(in: app, "clove.group").waitForExistence(timeout: 10),
            "The group view did not appear"
        )
    }

    /// Settings open from the group view.
    @MainActor
    private func openSettings(in app: XCUIApplication) {
        let settings = element(in: app, "clove.nav.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "The group view had no settings item")
        settings.tap()
        XCTAssertTrue(
            element(in: app, "clove.settings").waitForExistence(timeout: 10),
            "Settings did not appear"
        )
    }

    /// The first element carrying an accessibility identifier, whatever its element type.
    ///
    /// The shell, the screens and the chrome all set identifiers, and SwiftUI exposes them as
    /// different element types from run to run, so the test never depends on the type.
    @MainActor
    private func element(in app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }
}
