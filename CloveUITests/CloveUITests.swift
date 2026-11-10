import XCTest

/// The Clove UI smoke test: the grid's overlays, its filter, the grid group display setting,
/// multi-select's batch and its partial failure, and U1's path from entry to settings and back,
/// all against the in-memory test library (PRD Grid, P0-03, P0-09, P0-13).
final class CloveUITests: XCTestCase {
    @MainActor
    func testBrowsingFlowFromEntryToSettings() {
        let app = XCUIApplication()
        // The in-memory library, so the path needs no folder, fixture or permission.
        app.launchEnvironment["CLOVE_TEST_LIBRARY"] = "1"
        // Every sample photo whose stem ends in 0 fails its first write, so the batch below has a
        // partial failure to report and retry without a file (PRD P0-09).
        app.launchEnvironment["CLOVE_TEST_LIBRARY_FAIL_STEM_SUFFIX"] = "0"
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear"
        )

        openTestLibrary(in: app)
        checkGridOverlays(in: app)
        showOnlyRejectedThenAll(in: app)
        openFirstPhoto(in: app)
        checkDoubleTapZoom(in: app)
        markThePhoto(in: app)
        advanceByEdgeTap(in: app)
        returnToGrid(in: app)
        openGroup(in: app)
        openSettings(in: app)
        showGroupsAsCollapsedCovers(in: app)
        showGroupsAsExpandedCells(in: app)
        selectPhotosForABatch(in: app)
        rateTheSelection(in: app)
        retryTheFailedPhotos(in: app)
        leaveMultiSelect(in: app)
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

    /// Waits for an element's value with a tight poll, so an informational measurement is not
    /// dominated by XCTest's one-second predicate polling. The wait is bounded by `timeout`.
    @MainActor
    private func waitForValue(
        _ value: String, of element: XCUIElement, timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.value as? String == value { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return element.value as? String == value
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

    /// The grid opens the first photo's detail, which shows its preview, file name and marks.
    ///
    /// Identifiers carry the photo's identity stem, which is folded to lower case, so the first
    /// sample photo is `mmq02678`. The time from the tap to the preview's loaded state is
    /// informational only (G1's first detail preview target), never an assertion.
    @MainActor
    private func openFirstPhoto(in app: XCUIApplication) {
        let first = element(in: app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The grid did not show the first photo")
        let started = Date()
        first.tap()

        let preview = element(in: app, "clove.detail.preview")
        XCTAssertTrue(
            waitForValue("Loaded", of: preview, timeout: 10),
            "The detail preview did not load")
        let milliseconds = Date().timeIntervalSince(started) * 1000
        print("DETAIL_FIRST_PREVIEW_MS=\(Int(milliseconds.rounded()))")
        XCTContext.runActivity(
            named: "Detail open to first preview: \(Int(milliseconds.rounded())) ms"
        ) { _ in }

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

    /// A double tap in the middle goes to 100% and another returns to fit (PRD P0-04).
    @MainActor
    private func checkDoubleTapZoom(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        let zoom = element(in: app, "clove.detail.zoom")
        XCTAssertTrue(zoom.waitForExistence(timeout: 10), "The detail view had no zoom state")
        XCTAssertEqual(zoom.label, "Fit", "The detail view did not open at fit")

        preview.doubleTap()
        let full = expectation(
            for: NSPredicate(format: "label == %@", "100%"), evaluatedWith: zoom)
        wait(for: [full], timeout: 10)

        preview.doubleTap()
        let fit = expectation(for: NSPredicate(format: "label == %@", "Fit"), evaluatedWith: zoom)
        wait(for: [fit], timeout: 10)
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

    /// The right edge is a single-tap navigation zone, and it shows the next photo at once
    /// (PRD P0-04: edge taps navigate without waiting for a double tap).
    @MainActor
    private func advanceByEdgeTap(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The detail view had no preview")
        // The outer 18% on each side navigates; 94% is inside the right zone on any width.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()

        let fileName = element(in: app, "clove.detail.fileName")
        let next = expectation(
            for: NSPredicate(format: "label == %@", "MMQ02679.ARW"), evaluatedWith: fileName)
        wait(for: [next], timeout: 10)
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

    /// Settings switch the grid's group display; going back shows the test group as one cover
    /// cell instead of one cell per member (PRD Grid, Similar groups).
    @MainActor
    private func showGroupsAsCollapsedCovers(in app: XCUIApplication) {
        setGridGroupDisplay(in: app, to: "Collapsed")

        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Settings had no back button")
        back.tap()

        let cover = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(
            cover.waitForExistence(timeout: 10), "The collapsed grid showed no group cover")
        XCTAssertEqual(
            cover.label, "Similar group of 3 photos", "The cover lost its group's count")
        XCTAssertFalse(
            element(in: app, "clove.grid.photo.mmq02678").exists,
            "The collapsed grid still showed a group member as its own cell")
    }

    /// The same setting switched back shows every photo of the group again (PRD Grid).
    @MainActor
    private func showGroupsAsExpandedCells(in app: XCUIApplication) {
        let settings = element(in: app, "clove.nav.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "The grid had no settings item")
        settings.tap()
        setGridGroupDisplay(in: app, to: "Expanded")

        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Settings had no back button")
        back.tap()
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02678").waitForExistence(timeout: 10),
            "The expanded grid did not show a group member as its own cell")
    }

    /// Chooses one grid group display value on the settings screen (PRD Grid).
    @MainActor
    private func setGridGroupDisplay(in app: XCUIApplication, to name: String) {
        let picker = scrollToSettingsControl("clove.settings.gridGroupDisplay", in: app)
        XCTAssertTrue(picker.exists, "Settings had no grid display control")
        let option = picker.buttons[name]
        XCTAssertTrue(
            option.waitForExistence(timeout: 10),
            "The grid display control offered no \(name) option")
        option.tap()
    }

    /// Scrolls the settings list until one control is on screen (PRD Gesture-related settings).
    ///
    /// The list draws only the rows near the visible area, so a control in a later section has to
    /// be scrolled to before it exists. The number of swipes is bounded, so a missing control
    /// fails the check instead of hanging the run.
    @MainActor
    private func scrollToSettingsControl(
        _ identifier: String, in app: XCUIApplication, swipes: Int = 6
    ) -> XCUIElement {
        let control = element(in: app, identifier)
        for _ in 0..<swipes {
            if control.exists && control.isHittable { return control }
            app.swipeUp()
        }
        return control
    }

    /// The first element carrying an accessibility identifier, whatever its element type.
    ///
    /// The shell, the screens and the chrome all set identifiers, and SwiftUI exposes them as
    /// different element types from run to run, so the test never depends on the type.
    @MainActor
    private func element(in app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier]
    }

    /// A long press starts multi-select on that photo, and two taps add two more (PRD P0-09).
    @MainActor
    private func selectPhotosForABatch(in app: XCUIApplication) {
        let pressed = element(in: app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(
            pressed.waitForExistence(timeout: 10), "The grid did not show the first photo")
        pressed.press(forDuration: 1)

        let count = element(in: app, "clove.grid.batch.count")
        XCTAssertTrue(
            count.waitForExistence(timeout: 10), "A long press did not start multi-select")
        XCTAssertEqual(count.label, "1 photo selected", "The pressed photo was not selected")

        element(in: app, "clove.grid.photo.mmq02679").tap()
        element(in: app, "clove.grid.photo.mmq02680").tap()
        let three = expectation(
            for: NSPredicate(format: "label == %@", "3 photos selected"), evaluatedWith: count)
        wait(for: [three], timeout: 10)
    }

    /// The bar's rating reaches every selected photo, including the rejected one, whose Reject
    /// the positive rating clears (PRD P0-09, PRD Marking rules).
    @MainActor
    private func rateTheSelection(in app: XCUIApplication) {
        let twoStars = element(in: app, "clove.grid.batch.rate.2")
        XCTAssertTrue(twoStars.waitForExistence(timeout: 10), "The bar had no rating control")
        twoStars.tap()

        let first = element(in: app, "clove.grid.photo.mmq02678")
        let rated = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "2 stars"), evaluatedWith: first)
        let second = element(in: app, "clove.grid.photo.mmq02679")
        let alsoRated = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "2 stars"), evaluatedWith: second)
        wait(for: [rated, alsoRated], timeout: 10)
        XCTAssertFalse(
            second.label.contains("Rejected"), "A rating left Reject on: \(second.label)")
    }

    /// A partial batch failure shows the PRD copy and keeps the failed photo's marks; Retry
    /// resends only that photo and clears the report once it saves (PRD P0-09, PRD Failure and
    /// recovery).
    @MainActor
    private func retryTheFailedPhotos(in app: XCUIApplication) {
        let copy = "Saved 2 photos. 1 photos couldn't be saved."
        let failure = element(in: app, "clove.grid.batch.failure")
        XCTAssertTrue(
            failure.waitForExistence(timeout: 10), "The batch did not report its failure")
        XCTAssertEqual(failure.label, copy, "The partial-failure copy changed")
        // The report exists only after the batch finished, so this checks the final state: the
        // photo that failed keeps the marks it had (PRD P0-09, P0-08).
        let failed = element(in: app, "clove.grid.photo.mmq02680")
        XCTAssertFalse(
            failed.label.contains("stars"),
            "The grid showed a mark the batch did not save: \(failed.label)")

        element(in: app, "clove.grid.batch.retry").tap()
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: failure)
        wait(for: [gone], timeout: 10)

        let retried = element(in: app, "clove.grid.photo.mmq02680")
        let rated = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "2 stars"), evaluatedWith: retried)
        wait(for: [rated], timeout: 10)
    }

    /// Done leaves multi-select and clears the selection (PRD P0-09).
    @MainActor
    private func leaveMultiSelect(in app: XCUIApplication) {
        element(in: app, "clove.grid.batch.done").tap()
        let count = element(in: app, "clove.grid.batch.count")
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: count)
        wait(for: [gone], timeout: 10)
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02678").waitForExistence(timeout: 10),
            "The grid did not stay after multi-select")
    }
}
