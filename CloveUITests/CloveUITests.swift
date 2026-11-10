import XCTest

/// The Clove UI smoke test: the grid's overlays, its filter, the grid group display setting, the
/// detail's zoom and marking gestures, multi-select's batch and its partial failure, Move rejects
/// with its partial failure and retry, and U1's path from entry to settings and back, all against
/// the in-memory test library (PRD Grid, P0-03, P0-06, P0-09, P0-10, P0-13).
final class CloveUITests: XCTestCase {
    @MainActor
    func testBrowsingFlowFromEntryToSettings() {
        let app = XCUIApplication()
        // The in-memory library, so the path needs no folder, fixture or permission.
        app.launchEnvironment["CLOVE_TEST_LIBRARY"] = "1"
        // Every sample photo whose stem ends in 0 fails its first write, so the batch below has a
        // partial failure to report and retry without a file (PRD P0-09).
        app.launchEnvironment["CLOVE_TEST_LIBRARY_FAIL_STEM_SUFFIX"] = "0"
        // A rejected photo whose stem ends in 9 fails its first move once, so Move rejects can
        // report PRD's partial copy and retry without a file (PRD P0-10).
        app.launchEnvironment["CLOVE_TEST_LIBRARY_MOVE_FAIL_STEM_SUFFIX"] = "9"
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear"
        )

        openTestLibrary(in: app)
        checkGridOverlays(in: app)
        showOnlyRejectedThenAll(in: app)
        rerunGrouping(in: app)
        openFirstPhoto(in: app)
        checkDoubleTapZoom(in: app)
        markThePhoto(in: app)
        rateBySwiping(in: app)
        rejectBySwiping(in: app)
        advanceByEdgeTap(in: app)
        returnToGrid(in: app)
        openGroup(in: app)
        openSettings(in: app)
        showGroupsAsCollapsedCovers(in: app)
        showGroupsAsExpandedCells(in: app)
        hideAndShowSimilarGroups(in: app)
        selectPhotosForABatch(in: app)
        rateTheSelection(in: app)
        retryTheFailedPhotos(in: app)
        leaveMultiSelect(in: app)
        rejectPhotosForMove(in: app)
        checkMoveRejectsSetting(in: app)
        moveRejectsWithRetry(in: app)
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

    /// The grouping menu runs similar groups again and the grid keeps its group tag
    /// (PRD P0-11: Run again is always available; the test library's groups stay as they are).
    @MainActor
    private func rerunGrouping(in app: XCUIApplication) {
        selectMenuItem(in: app, "clove.grid.grouping", item: "clove.grid.grouping.runAgain")
        let group = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(
            group.waitForExistence(timeout: 10), "Run again dropped the grid's similar group")
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

        // A pinch still zooms, and while zoomed a one-finger drag pans instead of marking
        // (PRD Detail gestures: vertical marking swipes are disabled while zoomed).
        let saveState = element(in: app, "clove.detail.saveState")
        let marks = element(in: app, "clove.detail.marks")
        let marksAtFit = marks.label
        preview.pinch(withScale: 2, velocity: 1)
        let pinched = expectation(
            for: NSPredicate(format: "label != %@", "Fit"), evaluatedWith: zoom)
        wait(for: [pinched], timeout: 10)

        drag(preview, byPointsX: 0, y: -150)

        preview.doubleTap()
        let backToFit = expectation(
            for: NSPredicate(format: "label == %@", "Fit"), evaluatedWith: zoom)
        wait(for: [backToFit], timeout: 10)

        // A zoomed drag that marked would change the marks, and a write would show its own save
        // state or move the detail on, so what both read here stays as it was at fit.
        XCTAssertEqual(
            marks.label, marksAtFit, "The zoomed drag rated the photo instead of panning")
        XCTAssertEqual(saveState.label, "No change yet", "The zoomed drag wrote a mark")
    }

    /// A rating applied in detail writes through the seam, and the detail moves to the next photo
    /// after the pause (PRD P0-05, P0-08, PRD Auto-advance).
    @MainActor
    private func markThePhoto(in app: XCUIApplication) {
        let saveState = element(in: app, "clove.detail.saveState")
        XCTAssertTrue(saveState.waitForExistence(timeout: 10), "The detail view had no save state")
        XCTAssertEqual(saveState.label, "No change yet")

        let fourStars = element(in: app, "clove.detail.rate.4")
        XCTAssertTrue(
            fourStars.waitForExistence(timeout: 10), "The detail view had no rating buttons")
        fourStars.tap()

        // Only a written mark starts the default next-photo advance, and it follows the pause
        // (PRD Auto-advance), so the move is the proof the bar's mark was admitted; the grid
        // reads the rating back below, and the swipe's save state is read in `rateBySwiping`.
        waitForFileName("MMQ02679.ARW", in: app)
    }

    /// A swipe up two rating steps writes that rating, and the detail advances to the next photo
    /// after the pause; going back shows the written rating (PRD P0-06, PRD Auto-advance).
    ///
    /// The drag is a fixed 150 pt, so the step is the PRD's distance and not the screen height:
    /// 40 pt of dead zone plus two 60 pt steps puts step 2 between 100 and 160 pt.
    @MainActor
    private func rateBySwiping(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The detail view had no preview")
        waitForFileName("MMQ02679.ARW", in: app)

        drag(preview, byPointsX: 0, y: -150)

        // The mark is written on release and the default auto-advance follows after 0.3 s.
        waitForFileName("MMQ02680.ARW", in: app)

        // Back to the rated photo: the release position decided the rating, two steps up, and the
        // write it admitted is confirmed on screen (PRD P0-08).
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        waitForFileName("MMQ02679.ARW", in: app)
        let marks = element(in: app, "clove.detail.marks")
        let twoStars = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "2 stars"), evaluatedWith: marks)
        wait(for: [twoStars], timeout: 10)

        let saveState = element(in: app, "clove.detail.saveState")
        let saved = expectation(
            for: NSPredicate(format: "label == %@", "Saved"), evaluatedWith: saveState)
        wait(for: [saved], timeout: 10)
    }

    /// A swipe down past the threshold rejects the photo and advances like a rating does
    /// (PRD Detail gestures, PRD Auto-advance).
    @MainActor
    private func rejectBySwiping(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The detail view had no preview")
        waitForFileName("MMQ02679.ARW", in: app)

        drag(preview, byPointsX: 0, y: 130)

        // Reject is a written mark, so the default auto-advance moves on after the pause; the
        // grid check below reads the confirmed Reject back from the photo.
        waitForFileName("MMQ02680.ARW", in: app)
    }

    /// Drags a fixed number of points from the middle of an element, slowly enough for the
    /// preview's pan to track every step (PRD Rating by swipe distance).
    @MainActor
    private func drag(_ element: XCUIElement, byPointsX dx: CGFloat, y dy: CGFloat) {
        let middle = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: dx, dy: dy)))
    }

    /// Waits for the detail view to show one photo (PRD Detail and marking).
    @MainActor
    private func waitForFileName(_ name: String, in app: XCUIApplication) {
        let fileName = element(in: app, "clove.detail.fileName")
        let shown = expectation(
            for: NSPredicate(format: "label == %@", name), evaluatedWith: fileName)
        wait(for: [shown], timeout: 10)
    }

    /// The right edge is a single-tap navigation zone, and it shows the next photo at once
    /// (PRD P0-04: edge taps navigate without waiting for a double tap).
    @MainActor
    private func advanceByEdgeTap(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The detail view had no preview")
        waitForFileName("MMQ02680.ARW", in: app)
        // The outer 18% on each side navigates; 94% is inside the right zone on any width.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        waitForFileName("MMQ02681.ARW", in: app)
    }

    /// Back returns from detail to the grid, and the grid shows the marks the update path carried
    /// back through the library: the bar's rating, the swipe's rating and its Reject
    /// (PRD P0-03, P0-06, P0-08).
    @MainActor
    private func returnToGrid(in app: XCUIApplication) {
        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The detail view had no back button")
        back.tap()
        let row = element(in: app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "Back did not return to the grid")
        XCTAssertTrue(
            row.label.contains("4 stars"),
            "The grid did not show the rating the bar wrote: \(row.label)"
        )

        let swiped = element(in: app, "clove.grid.photo.mmq02679")
        XCTAssertTrue(swiped.exists, "The grid did not show the swiped photo")
        XCTAssertTrue(
            swiped.label.contains("2 stars"),
            "The grid did not show the rating the swipe wrote: \(swiped.label)"
        )
        XCTAssertTrue(
            swiped.label.contains("Rejected"),
            "The grid did not show the Reject the swipe wrote: \(swiped.label)"
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

    /// Turning similar groups off hides the grid's group and its Run again entry point, and
    /// turning them back on restores them (PRD Similar groups: that hides the entry points and
    /// blue outlines; the sample library answers the same call the real one does).
    @MainActor
    private func hideAndShowSimilarGroups(in app: XCUIApplication) {
        openSettingsFromGrid(in: app)
        setSimilarGroups(in: app, on: false)
        backToGrid(in: app)
        XCTAssertFalse(
            element(in: app, "clove.grid.group.burst-2678").waitForExistence(timeout: 3),
            "Turning similar groups off left the grid's similar group")
        XCTAssertFalse(
            element(in: app, "clove.grid.grouping").exists,
            "Turning similar groups off left the Run again menu")

        openSettingsFromGrid(in: app)
        setSimilarGroups(in: app, on: true)
        backToGrid(in: app)
        XCTAssertTrue(
            element(in: app, "clove.grid.group.burst-2678").waitForExistence(timeout: 10),
            "Turning similar groups back on did not restore the grid's similar group")
        XCTAssertTrue(
            element(in: app, "clove.grid.grouping").exists,
            "Turning similar groups back on did not restore the Run again menu")
    }

    /// Opens Settings from the grid (PRD Gesture-related settings).
    @MainActor
    private func openSettingsFromGrid(in app: XCUIApplication) {
        let settings = element(in: app, "clove.nav.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "The grid had no settings item")
        settings.tap()
        XCTAssertTrue(
            element(in: app, "clove.settings").waitForExistence(timeout: 10),
            "Settings did not appear"
        )
    }

    /// Taps the similar-groups switch; the sample starts with it on (PRD Similar groups).
    ///
    /// The switch is the last control of a long list, so it is scrolled fully into view before the
    /// tap: the list reports a row at the screen's bottom edge as hittable, where a tap lands
    /// outside the window.
    @MainActor
    private func setSimilarGroups(in app: XCUIApplication, on: Bool) {
        let toggle = element(in: app, "clove.settings.similarGroupsEnabled")
        let window = app.windows.firstMatch.frame
        for _ in 0..<8 {
            if toggle.exists && toggle.isHittable, toggle.frame.maxY < window.maxY - 120 {
                break
            }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.waitForExistence(timeout: 10), "Settings had no similar-groups switch")
        // A SwiftUI row toggle only flips on its switch, which sits at the trailing edge; a tap
        // in the middle of the row lands on the label.
        for _ in 0..<2 {
            if switchValue(toggle) == (on ? "1" : "0") { return }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(
            switchValue(toggle), on ? "1" : "0",
            "The similar-groups switch did not turn \(on ? "on" : "off")")
    }

    /// A toggle's accessibility value, "1" when it is on (PRD Similar groups).
    @MainActor
    private func switchValue(_ toggle: XCUIElement) -> String? {
        toggle.value as? String
    }

    /// Returns from Settings to the grid (PRD P0-13).
    @MainActor
    private func backToGrid(in app: XCUIApplication) {
        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Settings had no back button")
        back.tap()
        XCTAssertTrue(
            element(in: app, "clove.grid").waitForExistence(timeout: 10),
            "Back did not return to the grid"
        )
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
        // The sample starts with one more reject; rating it clears that Reject so the Move
        // rejects check below has exactly the two photos it rejects itself.
        element(in: app, "clove.grid.photo.mmq02685").tap()
        let four = expectation(
            for: NSPredicate(format: "label == %@", "4 photos selected"), evaluatedWith: count)
        wait(for: [four], timeout: 10)
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
        let sampleReject = element(in: app, "clove.grid.photo.mmq02685")
        let rejectCleared = expectation(
            for: NSPredicate(format: "NOT (label CONTAINS %@)", "Rejected"),
            evaluatedWith: sampleReject)
        wait(for: [rated, alsoRated, rejectCleared], timeout: 10)
        XCTAssertFalse(
            second.label.contains("Rejected"), "A rating left Reject on: \(second.label)")
    }

    /// A partial batch failure shows the PRD copy and keeps the failed photo's marks; Retry
    /// resends only that photo and clears the report once it saves (PRD P0-09, PRD Failure and
    /// recovery).
    @MainActor
    private func retryTheFailedPhotos(in app: XCUIApplication) {
        let copy = "Saved 3 photos. 1 photos couldn't be saved."
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

    /// Rejects two photos from the batch bar, so Move rejects has a known count to confirm
    /// (PRD P0-09, P0-10).
    @MainActor
    private func rejectPhotosForMove(in app: XCUIApplication) {
        let first = element(in: app, "clove.grid.photo.mmq02681")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The grid did not show the first photo")
        first.press(forDuration: 1)
        element(in: app, "clove.grid.photo.mmq02689").tap()

        let count = element(in: app, "clove.grid.batch.count")
        let two = expectation(
            for: NSPredicate(format: "label == %@", "2 photos selected"), evaluatedWith: count)
        wait(for: [two], timeout: 10)

        element(in: app, "clove.grid.batch.reject").tap()
        let rejected = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "Rejected"), evaluatedWith: first)
        wait(for: [rejected], timeout: 10)
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02689").label.contains("Rejected"),
            "The batch did not reject the second photo")

        element(in: app, "clove.grid.batch.done").tap()
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: count)
        wait(for: [gone], timeout: 10)
    }

    /// Move rejects shows the plan's count, keeps one reject, reports the forced move failure
    /// with Details, and its retry moves only the failure (design handoff, PRD P0-10).
    @MainActor
    private func moveRejectsWithRetry(in app: XCUIApplication) {
        let move = element(in: app, "clove.grid.moveRejects")
        XCTAssertTrue(
            move.waitForExistence(timeout: 10), "The grid did not offer Move rejects")
        move.tap()

        let confirmation = element(in: app, "clove.moves.confirmation")
        XCTAssertTrue(
            confirmation.waitForExistence(timeout: 10), "The confirmation sheet did not appear")
        XCTAssertEqual(
            confirmation.label, "Move 2 rejected photos",
            "The confirmation lost the rejected count")
        XCTAssertTrue(
            element(in: app, "clove.moves.body").label
                == "To _Rejected in this folder. Nothing is deleted.",
            "The confirmation lost the destination and no-delete promise")

        // Keep the photo that moves successfully, so the forced failure still exercises the
        // partial toast and Details while the other photo stays behind.
        element(in: app, "clove.moves.keep.mmq02681").tap()
        let partial = element(in: app, "clove.moves.partial")
        XCTAssertTrue(partial.waitForExistence(timeout: 10), "Keeping a photo changed no count")
        XCTAssertEqual(partial.label, "1 of 2 will move", "The staged keep count was wrong")
        XCTAssertEqual(
            element(in: app, "clove.moves.confirm").label, "Move 1",
            "The Move button did not follow the staged keep")

        element(in: app, "clove.moves.confirm").tap()

        let toast = element(in: app, "clove.moves.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "The move did not show its toast")
        let partialToast = expectation(
            for: NSPredicate(format: "label == %@", "Moved 0 to _Rejected"),
            evaluatedWith: toast)
        wait(for: [partialToast], timeout: 10)
        let failure = element(in: app, "clove.moves.toast.failure")
        XCTAssertEqual(
            failure.label, "1 couldn't be moved", "The partial toast changed its counts")

        // The kept photo is still in the grid and is no longer rejected; the failed photo stays
        // rejected in place.
        let kept = element(in: app, "clove.grid.photo.mmq02681")
        XCTAssertTrue(kept.exists, "The kept photo left the grid")
        XCTAssertFalse(
            kept.label.contains("Rejected"), "The kept photo kept its Reject: \(kept.label)")
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02689").label.contains("Rejected"),
            "A failed move cleared the photo's Reject")

        element(in: app, "clove.moves.details").tap()
        let detailsTitle = element(in: app, "clove.moves.details.subtitle")
        XCTAssertTrue(
            detailsTitle.waitForExistence(timeout: 10), "Details did not open its sheet")
        XCTAssertEqual(
            detailsTitle.label,
            "They stay rejected in Clove. Nothing was deleted.",
            "The details subtitle changed")
        XCTAssertTrue(
            element(in: app, "clove.moves.details.row.mmq02689").exists,
            "Details did not list the photo that could not move")

        element(in: app, "clove.moves.details.retry").tap()
        let retried = expectation(
            for: NSPredicate(format: "label == %@", "Moved 1 to _Rejected"),
            evaluatedWith: toast)
        wait(for: [retried], timeout: 10)

        let moved = element(in: app, "clove.grid.photo.mmq02689")
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: moved)
        wait(for: [gone], timeout: 10)
        XCTAssertTrue(kept.exists, "The retry moved the kept photo")
    }

    /// The Move rejects action shows while rejects exist and the setting is on, and turns off
    /// with the setting (design handoff, PRD P0-10).
    @MainActor
    private func checkMoveRejectsSetting(in app: XCUIApplication) {
        XCTAssertTrue(
            element(in: app, "clove.grid.moveRejects").waitForExistence(timeout: 10),
            "The grid did not offer Move rejects with rejected photos in the folder")

        openSettingsFromGrid(in: app)
        setMoveRejects(in: app, on: false)
        backToGrid(in: app)
        XCTAssertFalse(
            element(in: app, "clove.grid.moveRejects").waitForExistence(timeout: 3),
            "Turning Move rejects off left its grid action")

        openSettingsFromGrid(in: app)
        setMoveRejects(in: app, on: true)
        backToGrid(in: app)
        XCTAssertTrue(
            element(in: app, "clove.grid.moveRejects").waitForExistence(timeout: 10),
            "Turning Move rejects back on did not restore its grid action")
    }

    /// Taps the Move rejects switch, scrolling the settings list until it is on screen.
    @MainActor
    private func setMoveRejects(in app: XCUIApplication, on: Bool) {
        let toggle = scrollToSettingsControl("clove.settings.moveRejectsEnabled", in: app)
        XCTAssertTrue(toggle.exists, "Settings had no Move rejects switch")
        for _ in 0..<2 {
            if switchValue(toggle) == (on ? "1" : "0") { return }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(
            switchValue(toggle), on ? "1" : "0",
            "The Move rejects switch did not turn \(on ? "on" : "off")")
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
