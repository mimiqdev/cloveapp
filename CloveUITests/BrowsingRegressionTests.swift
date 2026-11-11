import XCTest

/// Restores the original browsing safety net, adapted only to the designed controls and glyphs.
extension CloveUITests {
    /// The Appearance setting keeps a chosen theme across a relaunch (V1, tokens.md).
    ///
    /// This launch uses the app's own settings storage rather than the sample library, because
    /// the check is that the next launch reads what this one stored. The test starts from Match
    /// system on and leaves it on, so the other tests see the usual appearance.
    @MainActor @objc
    func testAppearanceChoicePersistsAcrossLaunches() {
        addTeardownBlock { @MainActor in
            Self.restoreAppearance()
        }

        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear")
        openSettings(in: app)
        chooseAdvanceDestination("Next unmarked photo", in: app)
        setAutoAdvanceEnabled(false, in: app)
        _ = scrollToSettingsControl(
            "clove.settings.appearance.matchSystem", in: app, scrollsUp: false)
        setAppearanceMatchSystem(in: app, on: true)
        attachScreenshot(named: "settings-appearance-light")
        setAppearanceMatchSystem(in: app, on: false)

        let nord = app.buttons["clove.settings.appearance.theme.nord"]
        XCTAssertTrue(nord.waitForExistence(timeout: 10), "The theme picker had no Nord tile")
        nord.tap()
        XCTAssertTrue(
            waitForSelection(of: nord, timeout: 5), "Nord did not become the chosen theme")
        attachScreenshot(named: "settings-appearance-nord")

        app.terminate()
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The relaunched Clove did not appear")
        openSettings(in: app)
        let storedMatchSystem = app.switches["clove.settings.appearance.matchSystem"]
        XCTAssertTrue(
            waitForValue("0", of: storedMatchSystem, timeout: 10),
            "The relaunch lost Match system")
        XCTAssertTrue(
            waitForSelection(
                of: app.buttons["clove.settings.appearance.theme.nord"], timeout: 10),
            "The relaunch lost the chosen theme")

        setAutoAdvanceEnabled(true, in: app)
        let destination = scrollToSettingsControl("clove.settings.autoAdvanceDestination", in: app)
        XCTAssertTrue(
            destination.label.contains("Next unmarked photo")
                || String(describing: destination.value).contains("Next unmarked photo"),
            "Disabling and relaunching lost the remembered auto-advance destination")
        chooseAdvanceDestination("Next photo", in: app)
        _ = scrollToSettingsControl(
            "clove.settings.appearance.matchSystem", in: app, scrollsUp: false)

        // Matching the system again in a light simulator brings the Light theme back: the theme
        // follows the device, not the dark color scheme the app had set for Nord.
        setAppearanceMatchSystem(in: app, on: true)
        XCTAssertTrue(
            waitForSelection(of: app.buttons["clove.settings.appearance.theme.light"], timeout: 5),
            "Matching a light system did not bring the Light theme back")
    }

    @MainActor
    private func chooseAdvanceDestination(_ name: String, in app: XCUIApplication) {
        scrollToSettingsControl("clove.settings.autoAdvanceDestination", in: app).tap()
        app.buttons[name].firstMatch.tap()
    }

    @MainActor
    private func setAutoAdvanceEnabled(_ enabled: Bool, in app: XCUIApplication) {
        let toggle = scrollToSettingsControl(
            "clove.settings.autoAdvanceEnabled", in: app, scrollsUp: false)
        if switchValue(toggle) != (enabled ? "1" : "0") {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertTrue(waitForValue(enabled ? "1" : "0", of: toggle, timeout: 5))
    }

    /// Puts the app back on Match system light/dark and the Light theme after the appearance test,
    /// even when it failed, so the other tests never run in a theme it left behind.
    ///
    /// It is best effort: a missing element ends it instead of failing the run again.
    @MainActor
    private static func restoreAppearance() {
        let app = XCUIApplication()
        app.launch()
        guard app.descendants(matching: .any)["clove.root"].waitForExistence(timeout: 30) else {
            return
        }
        // The glass toolbar and Entry both expose this identifier.
        let settings = app.descendants(matching: .any).matching(identifier: "clove.nav.settings")
            .firstMatch
        guard settings.waitForExistence(timeout: 10) else { return }
        settings.tap()
        let toggle = app.switches["clove.settings.appearance.matchSystem"]
        guard toggle.waitForExistence(timeout: 10) else { return }

        // Matching off first, so choosing Light applies instead of being ignored.
        if toggle.value as? String == "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            waitForSwitch(toggle, value: "0", timeout: 5)
        }
        let light = app.buttons["clove.settings.appearance.theme.light"]
        if light.waitForExistence(timeout: 5) {
            light.tap()
        }
        if toggle.value as? String == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            waitForSwitch(toggle, value: "1", timeout: 5)
        }
    }

    /// Waits until a switch reports a value, with a bounded poll.
    @MainActor
    private static func waitForSwitch(
        _ toggle: XCUIElement, value: String, timeout: TimeInterval
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if toggle.value as? String == value { return }
            Thread.sleep(forTimeInterval: 0.05)
        }
    }

    /// Turns Match system light/dark on or off, and checks that the switch followed.
    ///
    /// A SwiftUI row toggle flips only on its switch, which sits at the trailing edge; a tap in
    /// the middle of the row lands on the label.
    @MainActor
    private func setAppearanceMatchSystem(in app: XCUIApplication, on: Bool) {
        let toggle = app.switches["clove.settings.appearance.matchSystem"]
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10), "Settings had no Match system switch")
        for _ in 0..<2 {
            if switchValue(toggle) == (on ? "1" : "0") { return }
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(
            switchValue(toggle), on ? "1" : "0",
            "Match system did not turn \(on ? "on" : "off")")
    }

    /// Waits until an element reports that it is selected, with a bounded timeout.
    @MainActor
    private func waitForSelection(of element: XCUIElement, timeout: TimeInterval) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isSelected == true"), object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    /// The opt-in design captures use the same switch handling as the restored appearance test.
    @MainActor
    func chooseTheme(_ theme: String, _ app: XCUIApplication) {
        setAppearanceMatchSystem(in: app, on: false)
        let tile = element(in: app, "clove.settings.appearance.theme.\(theme)")
        XCTAssertTrue(tile.waitForExistence(timeout: 5))
        tile.tap()
        XCTAssertTrue(waitForSelection(of: tile, timeout: 5))
    }

    @MainActor @objc
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
        // Keep the move toast up for the Details check; the user-facing timer stays unchanged.
        app.launchEnvironment["CLOVE_TEST_LIBRARY_KEEP_TOAST"] = "1"
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear"
        )

        checkEntryAndSettings(in: app)
        openTestLibrary(in: app)
        checkGridOverlays(in: app)
        showOnlyRejectedThenAll(in: app)
        rerunGrouping(in: app)
        openFirstPhoto(in: app)
        checkDoubleTapZoom(in: app)
        markThePhoto(in: app)
        rateBySwiping(in: app)
        rejectBySwiping(in: app)
        expandGroupFromFilmstrip(in: app)
        advanceByEdgeTap(in: app)
        returnToGrid(in: app)
        openGroup(in: app)
        cullTheGroup(in: app)
        openSettings(in: app)
        showGroupsAsCollapsedCovers(in: app)
        showGroupsAsExpandedCells(in: app)
        hideAndShowSimilarGroups(in: app)
        selectPhotosForABatch(in: app)
        rateTheSelection(in: app)
        retryTheFailedPhotos(in: app)
        leaveMultiSelect(in: app)
        clearFinishingReject(in: app)
        rejectPhotosForMove(in: app)
        checkMoveRejectsSetting(in: app)
        moveRejectsWithRetry(in: app)
    }

    @MainActor
    private func back(in app: XCUIApplication) {
        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "The screen had no back button")
        back.tap()
    }

    @MainActor
    private func attachScreenshot(named name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    private func checkEntryAndSettings(in app: XCUIApplication) {
        XCTAssertTrue(element(in: app, "clove.entry.openFolder").waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "96, Done")).firstMatch
                .waitForExistence(timeout: 5))
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Not connected, Reconnect")
            ).firstMatch.waitForExistence(timeout: 5))
        attachScreenshot(named: "entry-resume")
        element(in: app, "clove.nav.settings").tap()
        XCTAssertTrue(
            element(in: app, "clove.settings.section.appearance").waitForExistence(timeout: 5))
        XCTAssertTrue(
            element(in: app, "clove.settings.section.culling").waitForExistence(timeout: 5))
        XCTAssertTrue(element(in: app, "clove.settings.section.move").waitForExistence(timeout: 5))
        attachScreenshot(named: "settings-sections")
        back(in: app)
    }

    @MainActor
    private func openTestLibrary(in app: XCUIApplication) {
        let open = element(in: app, "clove.entry.openFolder")
        XCTAssertTrue(open.waitForExistence(timeout: 10), "Entry did not offer the test library")
        open.tap()
        if element(in: app, "clove.detail").waitForExistence(timeout: 2) { back(in: app) }
        XCTAssertTrue(
            element(in: app, "clove.grid").waitForExistence(timeout: 10),
            "The grid did not appear after opening the folder"
        )
    }

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

    @MainActor
    private func rerunGrouping(in app: XCUIApplication) {
        selectMenuItem(in: app, "clove.grid.grouping", item: "clove.grid.grouping.runAgain")
        let group = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(
            group.waitForExistence(timeout: 10), "Run again dropped the grid's similar group")
    }

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

    @MainActor
    private func selectMenuItem(
        in app: XCUIApplication, _ control: String, item: String
    ) {
        let menu = element(in: app, control == "clove.grid.grouping" ? "clove.grid.more" : control)
        XCTAssertTrue(menu.waitForExistence(timeout: 10), "The grid did not show \(control)")
        menu.tap()
        let choice = app.buttons[item]
        XCTAssertTrue(
            choice.waitForExistence(timeout: 10), "The menu did not offer \(item)")
        choice.tap()
    }

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
            (marks.value as? String)?.contains("5 stars") == true,
            "The detail view did not show the saved rating: \(String(describing: marks.value))"
        )
    }

    @MainActor
    private func checkDoubleTapZoom(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        let zoom = element(in: app, "clove.detail.zoom")
        XCTAssertTrue(zoom.waitForExistence(timeout: 10), "The detail view had no zoom state")
        let fitLabel = zoom.label
        XCTAssertFalse(fitLabel.contains("%"), "The detail view did not open at fit")

        preview.doubleTap()
        let full = expectation(
            for: NSPredicate(format: "label ENDSWITH %@", "100%"), evaluatedWith: zoom)
        wait(for: [full], timeout: 10)

        preview.doubleTap()
        let fit = expectation(
            for: NSPredicate(format: "label == %@", fitLabel), evaluatedWith: zoom)
        wait(for: [fit], timeout: 10)

        // A pinch still zooms, and while zoomed a one-finger drag pans instead of marking
        // (PRD Detail gestures: vertical marking swipes are disabled while zoomed).
        let saveState = element(in: app, "clove.detail.saveState")
        let marks = element(in: app, "clove.detail.marks")
        let marksAtFit = marks.value as? String
        preview.pinch(withScale: 2, velocity: 1)
        let pinched = expectation(
            for: NSPredicate(format: "label != %@", fitLabel), evaluatedWith: zoom)
        wait(for: [pinched], timeout: 10)

        drag(preview, byPointsX: 0, y: -150)

        preview.doubleTap()
        let backToFit = expectation(
            for: NSPredicate(format: "label == %@", fitLabel), evaluatedWith: zoom)
        wait(for: [backToFit], timeout: 10)

        // A zoomed drag that marked would change the marks, and a write would show its own save
        // state or move the detail on, so what both read here stays as it was at fit.
        XCTAssertEqual(
            marks.value as? String, marksAtFit, "The zoomed drag rated the photo instead of panning"
        )
        waitForSavedGlyph(saveState)
    }

    @MainActor
    private func waitForSavedGlyph(_ glyph: XCUIElement) {
        let saved = expectation(
            for: NSPredicate(format: "exists == true AND label == %@", "Saved"),
            evaluatedWith: glyph)
        wait(for: [saved], timeout: 10)
    }

    @MainActor
    private func markThePhoto(in app: XCUIApplication) {
        let saveState = element(in: app, "clove.detail.saveState")
        waitForSavedGlyph(saveState)

        let fourStars = element(in: app, "clove.detail.rate.4")
        XCTAssertTrue(
            fourStars.waitForExistence(timeout: 10), "The detail view had no rating buttons")
        fourStars.tap()

        // Only a written mark starts the default next-photo advance, and it follows the pause
        // (PRD Auto-advance), so the move is the proof the bar's mark was admitted; the grid
        // reads the rating back below, and the swipe's save state is read in `rateBySwiping`.
        waitForFileName("MMQ02679.ARW", in: app)
    }

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
            for: NSPredicate(format: "value CONTAINS %@", "2 stars"), evaluatedWith: marks)
        wait(for: [twoStars], timeout: 10)

        let saveState = element(in: app, "clove.detail.saveState")
        waitForSavedGlyph(saveState)
    }

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

    @MainActor
    private func drag(_ element: XCUIElement, byPointsX dx: CGFloat, y dy: CGFloat) {
        let middle = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: dx, dy: dy)))
    }

    @MainActor
    private func waitForFileName(_ name: String, in app: XCUIApplication) {
        let fileName = element(in: app, "clove.detail.fileName")
        let shown = expectation(
            for: NSPredicate(format: "label == %@", name), evaluatedWith: fileName)
        wait(for: [shown], timeout: 10)
    }

    @MainActor
    private func expandGroupFromFilmstrip(in app: XCUIApplication) {
        // MMQ02680 is outside the group, so the filmstrip shows the group as one stack.
        waitForFileName("MMQ02680.ARW", in: app)
        let stack = element(in: app, "clove.detail.filmstrip.group.burst-2678")
        XCTAssertTrue(stack.waitForExistence(timeout: 5), "The filmstrip did not stack the group")
        stack.tap()
        waitForFileName("MMQ02678.ARW", in: app)
        XCTAssertFalse(
            element(in: app, "clove.group").exists, "The filmstrip stack opened group review")
        let member = element(in: app, "clove.detail.filmstrip.mmq02679")
        XCTAssertTrue(
            member.waitForExistence(timeout: 5), "The group did not expand in the filmstrip")
        let back = element(in: app, "clove.detail.filmstrip.mmq02680")
        XCTAssertTrue(back.waitForExistence(timeout: 5), "The filmstrip lost the next photo")
        back.tap()
    }

    @MainActor
    private func advanceByEdgeTap(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        XCTAssertTrue(preview.waitForExistence(timeout: 10), "The detail view had no preview")
        waitForFileName("MMQ02680.ARW", in: app)
        // The outer 18% on each side navigates; 94% is inside the right zone on any width.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        waitForFileName("MMQ02681.ARW", in: app)
    }

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
            swiped.label.contains("Rejected"),
            "The grid did not show the Reject the swipe wrote: \(swiped.label)"
        )
        // Reject is rating −1, so swipe down replaced the swipe up's stars.
        XCTAssertFalse(
            swiped.label.contains("2 stars"),
            "A rejected photo kept its stars: \(swiped.label)"
        )
        XCTAssertFalse(
            swiped.label.contains("-1"),
            "A rejected photo read its rating: \(swiped.label)"
        )
    }

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

    @MainActor
    private func cullTheGroup(in app: XCUIApplication) {
        // The group opens at its first undecided photo, with detail's capsule.
        XCTAssertEqual(groupHeader(in: app).label, "1 undecided")
        let capsule = element(in: app, "clove.detail.capsule")
        XCTAssertTrue(waitForValue("Unmarked", of: capsule, timeout: 5))
        element(in: app, "clove.detail.capsule.stars.3").tap()
        XCTAssertTrue(element(in: app, "clove.group.continue").waitForExistence(timeout: 5))
        element(in: app, "clove.group.continue").tap()
        waitForFileName("MMQ02680.ARW", in: app)
        back(in: app)

        let nextGroup = element(in: app, "clove.grid.group.burst-2696")
        for _ in 0..<4 {
            if nextGroup.exists && nextGroup.isHittable { break }
            app.swipeUp()
        }
        nextGroup.tap()
        element(in: app, "clove.detail.capsule.stars.4").tap()
        XCTAssertEqual(groupHeader(in: app).label, "2 undecided")
        XCTAssertTrue(waitForValue("Unmarked", of: capsule, timeout: 5))
        element(in: app, "clove.detail.capsule.stars.3").tap()
        XCTAssertEqual(groupHeader(in: app).label, "1 undecided")
        XCTAssertTrue(waitForValue("Unmarked", of: capsule, timeout: 5))
        element(in: app, "clove.group.rejectUnmarked").tap()
        XCTAssertTrue(element(in: app, "clove.group.continue").waitForExistence(timeout: 5))
        element(in: app, "clove.group.continue").tap()
        waitForFileName("MMQ02699.ARW", in: app)
        back(in: app)
        checkTheFinishingRejects(in: app)
    }

    @MainActor
    private func checkTheFinishingRejects(in app: XCUIApplication) {
        selectMenuItem(in: app, "clove.grid.filter", item: "clove.grid.filter.rejected")

        let rejected = element(in: app, "clove.grid.photo.mmq02698")
        XCTAssertTrue(
            rejected.waitForExistence(timeout: 10),
            "Reject unmarked left the unmarked photo unrejected")
        XCTAssertTrue(
            rejected.label.contains("Rejected"), "The unmarked photo lost its Reject")
        XCTAssertFalse(
            element(in: app, "clove.grid.photo.mmq02696").exists,
            "The finishing action rejected a rated photo")
        XCTAssertFalse(
            element(in: app, "clove.grid.photo.mmq02697").exists,
            "The finishing action rejected the photo it kept")
        XCTAssertFalse(
            element(in: app, "clove.grid.photo.mmq02678").exists,
            "The finishing action rejected a rated and labelled photo")

        selectMenuItem(in: app, "clove.grid.filter", item: "clove.grid.filter.all")
    }

    @MainActor
    private func groupHeader(in app: XCUIApplication) -> XCUIElement {
        element(in: app, "clove.group.undecided")
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        if element(in: app, "clove.grid").exists {
            openSettingsFromGrid(in: app)
            return
        }
        let settings = element(in: app, "clove.nav.settings")
        XCTAssertTrue(settings.waitForExistence(timeout: 10), "The group view had no settings item")
        settings.tap()
        XCTAssertTrue(
            element(in: app, "clove.settings").waitForExistence(timeout: 10),
            "Settings did not appear"
        )
    }

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

    @MainActor
    private func showGroupsAsExpandedCells(in app: XCUIApplication) {
        openSettingsFromGrid(in: app)
        setGridGroupDisplay(in: app, to: "Expanded")

        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 10), "Settings had no back button")
        back.tap()
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02678").waitForExistence(timeout: 10),
            "The expanded grid did not show a group member as its own cell")
    }

    @MainActor
    private func hideAndShowSimilarGroups(in app: XCUIApplication) {
        openSettingsFromGrid(in: app)
        setSimilarGroups(in: app, on: false)
        backToGrid(in: app)
        XCTAssertFalse(
            element(in: app, "clove.grid.group.burst-2678").waitForExistence(timeout: 3),
            "Turning similar groups off left the grid's similar group")
        XCTAssertFalse(
            groupingActionIsVisible(in: app), "Turning similar groups off left Run again")

        openSettingsFromGrid(in: app)
        setSimilarGroups(in: app, on: true)
        backToGrid(in: app)
        XCTAssertTrue(
            element(in: app, "clove.grid.group.burst-2678").waitForExistence(timeout: 10),
            "Turning similar groups back on did not restore the grid's similar group")
        XCTAssertTrue(
            groupingActionIsVisible(in: app),
            "Turning similar groups back on did not restore Run again")
    }

    @MainActor
    private func groupingActionIsVisible(in app: XCUIApplication) -> Bool {
        element(in: app, "clove.grid.more").tap()
        let present = element(in: app, "clove.grid.grouping.runAgain").exists
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.6)).tap()
        return present
    }

    @MainActor
    private func openSettingsFromGrid(in app: XCUIApplication) {
        element(in: app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(
            element(in: app, "clove.settings").waitForExistence(timeout: 10),
            "Settings did not appear"
        )
    }

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

    @MainActor
    private func switchValue(_ toggle: XCUIElement) -> String? {
        toggle.value as? String
    }

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

    @MainActor
    private func scrollToSettingsControl(
        _ identifier: String, in app: XCUIApplication, swipes: Int = 6, scrollsUp: Bool = true
    ) -> XCUIElement {
        let control = element(in: app, identifier)
        for _ in 0..<swipes {
            if control.exists && control.isHittable { return control }
            if scrollsUp { app.swipeUp() } else { app.swipeDown() }
        }
        return control
    }

    @MainActor
    private func element(in app: XCUIApplication, _ identifier: String) -> XCUIElement {
        let direct = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        if identifier.hasPrefix("clove.grid.batch.rate.") {
            return app.descendants(matching: .any).matching(
                identifier: identifier.replacingOccurrences(of: ".rate.", with: ".stars.")
            ).firstMatch
        }
        if identifier.hasPrefix("clove.detail.rate."), !direct.exists {
            return app.descendants(matching: .any).matching(
                identifier: identifier.replacingOccurrences(of: ".rate.", with: ".capsule.stars.")
            ).firstMatch
        }
        if identifier == "clove.detail.marks", !direct.exists {
            return app.descendants(matching: .any).matching(identifier: "clove.detail.capsule")
                .firstMatch
        }
        return direct
    }

    @MainActor
    private func selectPhotosForABatch(in app: XCUIApplication) {
        let pressed = element(in: app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(
            pressed.waitForExistence(timeout: 10), "The grid did not show the first photo")
        pressed.press(forDuration: 1)

        let count = element(in: app, "clove.grid.batch.count")
        XCTAssertTrue(
            count.waitForExistence(timeout: 10), "A long press did not start multi-select")
        XCTAssertEqual(count.label, "1 selected", "The pressed photo was not selected")

        element(in: app, "clove.grid.photo.mmq02679").tap()
        element(in: app, "clove.grid.photo.mmq02680").tap()
        // The sample starts with one more reject; rating it clears that Reject so the Move
        // rejects check below has exactly the two photos it rejects itself.
        element(in: app, "clove.grid.photo.mmq02685").tap()
        let four = expectation(
            for: NSPredicate(format: "label == %@", "4 selected"), evaluatedWith: count)
        wait(for: [four], timeout: 10)
    }

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

    @MainActor
    private func retryTheFailedPhotos(in app: XCUIApplication) {
        let copy = "Save failed. Double-tap to retry."
        let failure = element(in: app, "clove.grid.saveState")
        let reported = expectation(
            for: NSPredicate(format: "exists == true AND label == %@", copy),
            evaluatedWith: failure)
        wait(for: [reported], timeout: 10)
        XCTAssertEqual(failure.label, copy, "The partial-failure copy changed")
        // Failure leaves the user's requested marks visible and unsaved until retry confirms.
        let failed = element(in: app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(
            failed.label.contains("2 stars"),
            "The failed photo lost its desired mark: \(failed.label)")

        failure.tap()
        let confirmed = expectation(
            for: NSPredicate(format: "label != %@", copy), evaluatedWith: failure)
        wait(for: [confirmed], timeout: 10)

        let retried = element(in: app, "clove.grid.photo.mmq02680")
        let rated = expectation(
            for: NSPredicate(format: "label CONTAINS %@", "2 stars"), evaluatedWith: retried)
        wait(for: [rated], timeout: 10)
    }

    @MainActor
    private func clearFinishingReject(in app: XCUIApplication) {
        selectMenuItem(in: app, "clove.grid.filter", item: "clove.grid.filter.rejected")
        let rejected = element(in: app, "clove.grid.photo.mmq02698")
        XCTAssertTrue(
            rejected.waitForExistence(timeout: 10),
            "The group view's finishing reject was not in the filtered grid")
        rejected.press(forDuration: 1)

        let count = element(in: app, "clove.grid.batch.count")
        XCTAssertTrue(
            count.waitForExistence(timeout: 10), "The finishing reject did not start a selection")
        element(in: app, "clove.grid.batch.rate.2").tap()
        let cleared = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: rejected)
        wait(for: [cleared], timeout: 10)

        element(in: app, "clove.grid.batch.done").tap()
        selectMenuItem(in: app, "clove.grid.filter", item: "clove.grid.filter.all")
    }

    @MainActor
    private func rejectPhotosForMove(in app: XCUIApplication) {
        let first = element(in: app, "clove.grid.photo.mmq02681")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The grid did not show the first photo")
        first.press(forDuration: 1)
        element(in: app, "clove.grid.photo.mmq02689").tap()

        let count = element(in: app, "clove.grid.batch.count")
        let two = expectation(
            for: NSPredicate(format: "label == %@", "2 selected"), evaluatedWith: count)
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
        element(in: app, "clove.moves.expand").tap()
        element(in: app, "clove.moves.keep.mmq02681").tap()
        let partial = element(in: app, "clove.moves.partial")
        XCTAssertTrue(partial.waitForExistence(timeout: 10), "Keeping a photo changed no count")
        XCTAssertEqual(partial.label, "1 of 2 will move", "The staged keep count was wrong")
        XCTAssertEqual(
            element(in: app, "clove.moves.confirm").label, "Move 1",
            "The Move button did not follow the staged keep")

        element(in: app, "clove.moves.confirm").tap()

        let toast = app.staticTexts["Moved 0 to _Rejected"]
        XCTAssertTrue(toast.waitForExistence(timeout: 10), "The move did not show its toast")
        let partialToast = expectation(
            for: NSPredicate(format: "label == %@", "Moved 0 to _Rejected"),
            evaluatedWith: toast)
        wait(for: [partialToast], timeout: 10)
        let failure = app.staticTexts["1 couldn't be moved"]
        XCTAssertEqual(
            failure.label, "1 couldn't be moved", "The partial toast changed its counts")

        // Details opens before the other grid queries, so a long test run never races the toast.
        element(in: app, "clove.moves.toast.action").tap()
        let detailsTitle = element(in: app, "clove.moves.details.subtitle")
        XCTAssertTrue(
            detailsTitle.waitForExistence(timeout: 10), "Details did not open its sheet")
        XCTAssertEqual(
            detailsTitle.label,
            "They stay rejected in place. Nothing was deleted.",
            "The details subtitle changed")
        XCTAssertTrue(
            element(in: app, "clove.moves.details.row.mmq02689").exists,
            "Details did not list the photo that could not move")

        element(in: app, "clove.moves.details.retry").tap()
        XCTAssertTrue(app.staticTexts["Moved 1 to _Rejected"].waitForExistence(timeout: 10))

        let kept = element(in: app, "clove.grid.photo.mmq02681")
        XCTAssertTrue(kept.exists, "The retry moved the kept photo")
        XCTAssertFalse(
            kept.label.contains("Rejected"), "The kept photo kept its Reject: \(kept.label)")
        let moved = element(in: app, "clove.grid.photo.mmq02689")
        let gone = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: moved)
        wait(for: [gone], timeout: 10)
    }

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
