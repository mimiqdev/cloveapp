import XCTest

/// Restores the original browsing safety net, adapted only to the designed controls and glyphs.
extension CloveFlowTests {
    /// The Appearance setting keeps a chosen theme across a relaunch (V1, tokens.md).
    ///
    /// This launch uses the app's own settings storage rather than the sample library, because
    /// the check is that the next launch reads what this one stored. The teardown puts Match
    /// system back on, so the other tests see the usual appearance. What is stored and how a
    /// theme resolves are CloveCore's: `savingAndLoadingRoundTripsEveryField`,
    /// `userDefaultsStorageRoundTripsUnderOneVersionedNamespace` and
    /// `matchingTheSystemPicksLightOrDark`.
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
        _ = scrollToSettingsControl(
            "clove.settings.appearance.matchSystem", in: app, scrollsUp: false)
        setAppearanceMatchSystem(in: app, on: false)

        let nord = app.buttons["clove.settings.appearance.theme.nord"]
        XCTAssertTrue(nord.exists, "The theme picker had no Nord tile")
        nord.tap()
        XCTAssertTrue(nord.isSelected, "Nord did not become the chosen theme")

        app.terminate()
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The relaunched Clove did not appear")
        openSettings(in: app)
        let storedMatchSystem = app.switches["clove.settings.appearance.matchSystem"]
        XCTAssertEqual(storedMatchSystem.value as? String, "0", "The relaunch lost Match system")
        XCTAssertTrue(
            app.buttons["clove.settings.appearance.theme.nord"].isSelected,
            "The relaunch lost the chosen theme")
    }

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
        guard settings.exists else { return }
        settings.tap()
        let toggle = app.switches["clove.settings.appearance.matchSystem"]
        guard toggle.exists else { return }

        // Matching off first, so choosing Light applies instead of being ignored.
        if toggle.value as? String == "1" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "0")
        }
        let light = app.buttons["clove.settings.appearance.theme.light"]
        if light.exists {
            light.tap()
        }
        if toggle.value as? String == "0" {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            XCTAssertEqual(toggle.value as? String, "1")
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
            toggle.exists, "Settings had no Match system switch")
        if switchValue(toggle) != (on ? "1" : "0") {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(
            switchValue(toggle), on ? "1" : "0",
            "Match system did not turn \(on ? "on" : "off")")
    }

    /// The opt-in design captures use the same switch handling as the restored appearance test.
    @MainActor
    func chooseTheme(_ theme: String, _ app: XCUIApplication) {
        setAppearanceMatchSystem(in: app, on: false)
        let tile = element(in: app, "clove.settings.appearance.theme.\(theme)")
        tile.tap()
        XCTAssertTrue(tile.isSelected)
    }

    /// The browsing path through the real controls, from Entry to the grid, detail, the
    /// filmstrip and the settings that change the grid.
    ///
    /// Steps other tests cover are not repeated here:
    /// - the group's finishing actions: `testStackOpensDetailAndFinishingUndoRestoresUnmarkedTogether`,
    ///   `undecidedCountsLabelOnlyRatedRejectedAndUnmarkedPhotos`,
    ///   `rejectingUnmarkedFinishesAGroupWithOnlyALabelledKeep`;
    /// - a batch rating with a failed write: `testSaveFailureShowsToastAndTheFilesMarks`,
    ///   `aBatchFailureShowsOneToastAndRestoresOnlyItsFailedPhoto`,
    ///   `aRatingSetsEveryPhotoAndReplacesRejectOnRejectedPhotos`;
    /// - the Rejected filter: `rejectedShowsRejectedPhotosOnly`;
    /// - Move rejects with a keep and a failure:
    ///   `testMoveRejectsConfirmsAndReportsFilesLeftInPlace`,
    ///   `RejectMoveCopyTests`.
    @MainActor @objc
    func testBrowsingFlowFromEntryToSettings() {
        let app = XCUIApplication()
        // The in-memory library, so the path needs no folder, fixture or permission.
        app.launchEnvironment["CLOVE_TEST_LIBRARY"] = "1"
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear"
        )

        checkEntryAndSettings(in: app)
        openTestLibrary(in: app)
        checkGridOverlays(in: app)
        rerunGrouping(in: app)
        openFirstPhoto(in: app)
        checkDoubleTapZoom(in: app)
        markThePhoto(in: app)
        rateBySwiping(in: app)
        rejectBySwiping(in: app)
        expandGroupFromFilmstrip(in: app)
        advanceBySwipe(in: app)
        returnToGrid(in: app)
        openSettings(in: app)
        showGroupsAsCollapsedCovers(in: app)
        showGroupsAsExpandedCells(in: app)
        hideAndShowSimilarGroups(in: app)
        rejectPhotosForMove(in: app)
        checkMoveRejectsSetting(in: app)
    }

    @MainActor
    private func back(in app: XCUIApplication) {
        let back = element(in: app, "clove.nav.back")
        // A just-pushed screen publishes its container before its header's back button, so this
        // waits on the observed state rather than one immediate snapshot (#212).
        XCTAssertTrue(
            back.waitForExistence(timeout: 10), "The screen had no back button")
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
        XCTAssertTrue(element(in: app, "clove.entry.openFolder").exists)
        XCTAssertTrue(
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "96, Done")).firstMatch
                .exists)
        XCTAssertTrue(
            app.buttons.matching(
                NSPredicate(format: "label CONTAINS %@", "Drive not connected, Reconnect")
            ).firstMatch.exists)
        attachScreenshot(named: "entry-resume")
        element(in: app, "clove.nav.settings").tap()
        XCTAssertTrue(
            element(in: app, "clove.settings.section.appearance").exists)
        XCTAssertTrue(
            element(in: app, "clove.settings.section.culling").exists)
        XCTAssertTrue(element(in: app, "clove.settings.section.move").exists)
        attachScreenshot(named: "settings-sections")
        back(in: app)
    }

    @MainActor
    private func openTestLibrary(in app: XCUIApplication) {
        let open = element(in: app, "clove.entry.openFolder")
        XCTAssertTrue(open.exists, "Entry did not offer the test library")
        open.tap()
        // The hero resumes the folder at its last-viewed photo, so detail can be the first
        // screen this open shows. The pushed screen's chrome is deferred (its container reaches
        // the accessibility tree before the back button), so this boundary reads the observed
        // outcome instead of one immediate snapshot (#193, #210).
        if element(in: app, "clove.detail").waitForExistence(timeout: 2) { back(in: app) }
        XCTAssertTrue(
            element(in: app, "clove.grid").waitForExistence(timeout: 10),
            "The grid did not appear after opening the folder"
        )
    }

    @MainActor
    private func checkGridOverlays(in app: XCUIApplication) {
        let rated = element(in: app, "clove.grid.photo.mmq02678")
        let ratedLabel = rated.label
        XCTAssertTrue(ratedLabel.contains("MMQ02678.ARW"), "The cell lost its file name")
        XCTAssertTrue(ratedLabel.contains("5 stars"), "The cell lost its rating: \(ratedLabel)")
        XCTAssertTrue(ratedLabel.contains("Red"), "The cell lost its colour dot: \(ratedLabel)")

        let rejected = element(in: app, "clove.grid.photo.mmq02679")
        let rejectedLabel = rejected.label
        XCTAssertTrue(
            rejectedLabel.contains("Rejected"), "The cell lost its Reject flag: \(rejectedLabel)")

        let companion = element(in: app, "clove.grid.photo.mmq02680")
        let companionLabel = companion.label
        XCTAssertTrue(
            companionLabel.contains("JPEG companion"),
            "The cell lost its companion badge: \(companionLabel)")
    }

    @MainActor
    private func rerunGrouping(in app: XCUIApplication) {
        selectMenuItem(in: app, "clove.grid.grouping", item: "clove.grid.grouping.runAgain")
        let group = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(
            group.waitForExistence(timeout: 10), "Run again dropped the grid's similar group")
    }

    @MainActor
    private func selectMenuItem(
        in app: XCUIApplication, _ control: String, item: String
    ) {
        let menu = element(in: app, control == "clove.grid.grouping" ? "clove.grid.more" : control)
        XCTAssertTrue(menu.exists, "The grid did not show \(control)")
        menu.tap()
        let choice = app.buttons[item]
        XCTAssertTrue(
            choice.exists, "The menu did not offer \(item)")
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
            wait(NSPredicate(format: "value == %@", "Loaded"), preview, timeout: 10),
            "The detail preview did not load")
        let milliseconds = Date().timeIntervalSince(started) * 1000
        print("DETAIL_FIRST_PREVIEW_MS=\(Int(milliseconds.rounded()))")
        XCTContext.runActivity(
            named: "Detail open to first preview: \(Int(milliseconds.rounded())) ms"
        ) { _ in }

        let fileName = element(in: app, "clove.detail.fileName")
        XCTAssertTrue(
            fileName.label == "MMQ02678.ARW", "The detail view did not show the file name")

        let marks = detailMarksControl(in: app).value as? String
        XCTAssertTrue(
            marks?.contains("5 stars") == true,
            "The detail view did not show the saved rating: \(String(describing: marks))"
        )
    }

    @MainActor
    private func checkDoubleTapZoom(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        let zoom = element(in: app, "clove.detail.zoom")
        let strip = element(in: app, "clove.detail.filmstrip")
        let fitLabel = zoom.label
        XCTAssertFalse(fitLabel.isEmpty, "The detail view had no zoom state")
        XCTAssertFalse(fitLabel.contains("%"), "The detail view did not open at fit")

        preview.doubleTap()
        XCTAssertTrue(zoom.label.hasSuffix("100%"))
        XCTAssertTrue(strip.exists, "The filmstrip should stay visible while zoomed")

        preview.doubleTap()
        XCTAssertEqual(zoom.label, fitLabel)

        // A pinch still zooms, and while zoomed a one-finger drag pans instead of marking
        // (PRD Detail gestures: vertical marking swipes are disabled while zoomed).
        let marks = detailMarksControl(in: app)
        let marksAtFit = marks.value as? String
        preview.pinch(withScale: 2, velocity: 1)
        XCTAssertNotEqual(zoom.label, fitLabel)
        XCTAssertTrue(strip.exists, "The filmstrip should stay visible after pinching to zoom")

        drag(preview, byPointsX: 0, y: -150)

        preview.doubleTap()
        XCTAssertEqual(zoom.label, fitLabel)

        // A zoomed drag that marked would change the marks, and a write would show its own save
        // state or move the detail on, so what both read here stays as it was at fit.
        XCTAssertEqual(
            marks.value as? String, marksAtFit, "The zoomed drag rated the photo instead of panning"
        )
    }

    @MainActor
    private func markThePhoto(in app: XCUIApplication) {
        if element(in: app, "clove.detail.rail").exists {
            element(in: app, "clove.detail.rail.stars.4").tap()
        } else {
            // The compact toolbar's rating action opens the ladder the stars live in (#227).
            element(in: app, "clove.detail.capsule.rating").tap()
            let fourStars = element(in: app, "clove.detail.capsule.stars.4")
            XCTAssertTrue(
                fourStars.waitForExistence(timeout: 5), "the rating ladder did not open")
            fourStars.tap()
        }

        // Group auto-advance skips the already rejected member. Select it explicitly for the
        // swipe checks below, which replace its existing Reject with stars.
        waitForFileName("MMQ02681.ARW", in: app)
        element(in: app, "clove.detail.filmstrip.mmq02679").tap()
        XCTAssertEqual(element(in: app, "clove.detail.fileName").label, "MMQ02679.ARW")
    }

    @MainActor
    private func rateBySwiping(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        let fileName = element(in: app, "clove.detail.fileName")
        XCTAssertEqual(fileName.label, "MMQ02679.ARW")

        // From Reject, three 60 pt ladder steps reach two stars (Reject → clear → 1 → 2).
        drag(preview, byPointsX: 0, y: -210)

        // The mark advances to the group's remaining unmarked member.
        waitForFileName("MMQ02681.ARW", in: app)

        // Return to the rated member through the expanded group.
        element(in: app, "clove.detail.filmstrip.mmq02679").tap()
        XCTAssertEqual(fileName.label, "MMQ02679.ARW")
        let marks = detailMarksControl(in: app)
        XCTAssertTrue((marks.value as? String)?.contains("2 stars") == true)

    }

    @MainActor
    private func rejectBySwiping(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        let fileName = element(in: app, "clove.detail.fileName")
        XCTAssertEqual(fileName.label, "MMQ02679.ARW")

        // Cross both the quick Reject threshold and all three slow steps from two stars.
        drag(preview, byPointsX: 0, y: 210)

        // Reject also advances within the group. A swipe right then returns to the interleaved
        // single photo for the general filmstrip and navigation checks.
        waitForFileName("MMQ02681.ARW", in: app)
        preview.swipeRight()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
    }

    @MainActor
    private func drag(_ element: XCUIElement, byPointsX dx: CGFloat, y dy: CGFloat) {
        let middle = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: dx, dy: dy)))
    }

    @MainActor
    private func waitForFileName(_ name: String, in app: XCUIApplication) {
        let fileName = element(in: app, "clove.detail.fileName")
        XCTAssertTrue(wait(NSPredicate(format: "label == %@", name), fileName, timeout: 10))
    }

    @MainActor
    private func expandGroupFromFilmstrip(in app: XCUIApplication) {
        // MMQ02680 is outside the group, so the filmstrip shows the group as one stack.
        XCTAssertEqual(element(in: app, "clove.detail.fileName").label, "MMQ02680.ARW")
        let stack = element(in: app, "clove.detail.filmstrip.group.burst-2678")
        stack.tap()
        XCTAssertEqual(element(in: app, "clove.detail.fileName").label, "MMQ02678.ARW")
        XCTAssertTrue(element(in: app, "clove.detail").exists)
        let member = element(in: app, "clove.detail.filmstrip.mmq02679")
        XCTAssertTrue(
            member.exists, "The group did not expand in the filmstrip")
        let back = element(in: app, "clove.detail.filmstrip.mmq02680")
        XCTAssertTrue(back.exists, "The filmstrip lost the next photo")
        back.tap()
    }

    @MainActor
    private func advanceBySwipe(in app: XCUIApplication) {
        let preview = element(in: app, "clove.detail.preview")
        let fileName = element(in: app, "clove.detail.fileName")
        let chromeTarget = element(
            in: app,
            element(in: app, "clove.detail.rail").exists
                ? "clove.detail.filmstrip" : "clove.detail.capsule")
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        // Single taps anywhere (including the outer 18% edges) toggle chrome and never navigate.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), chromeTarget))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), chromeTarget))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        preview.swipeLeft()
        XCTAssertEqual(fileName.label, "MMQ02681.ARW")
    }

    @MainActor
    private func detailMarksControl(in app: XCUIApplication) -> XCUIElement {
        let rail = element(in: app, "clove.detail.rail")
        return rail.exists ? rail : element(in: app, "clove.detail.capsule")
    }

    @MainActor
    private func returnToGrid(in app: XCUIApplication) {
        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.exists, "The detail view had no back button")
        back.tap()
        let row = element(in: app, "clove.grid.photo.mmq02678")
        let rowLabel = row.label
        XCTAssertTrue(
            rowLabel.contains("4 stars"),
            "The grid did not show the rating the bar wrote: \(rowLabel)"
        )

        let swiped = element(in: app, "clove.grid.photo.mmq02679")
        let swipedLabel = swiped.label
        XCTAssertTrue(
            swipedLabel.contains("Rejected"),
            "The grid did not show the Reject the swipe wrote: \(swipedLabel)"
        )
        // Reject is rating −1, so swipe down replaced the swipe up's stars.
        XCTAssertFalse(
            swipedLabel.contains("2 stars"), "A rejected photo kept its stars: \(swipedLabel)")
        XCTAssertFalse(
            swipedLabel.contains("-1"), "A rejected photo read its rating: \(swipedLabel)")
    }

    @MainActor
    private func openSettings(in app: XCUIApplication) {
        if element(in: app, "clove.grid").exists {
            openSettingsFromGrid(in: app)
            return
        }
        let settings = element(in: app, "clove.nav.settings")
        XCTAssertTrue(settings.exists, "The screen had no settings item")
        settings.tap()
        XCTAssertTrue(
            element(in: app, "clove.settings").exists,
            "Settings did not appear"
        )
    }

    @MainActor
    private func showGroupsAsCollapsedCovers(in app: XCUIApplication) {
        setGridGroupDisplay(in: app, to: "Collapsed")

        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.exists, "Settings had no back button")
        back.tap()

        let cover = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(
            cover.exists, "The collapsed grid showed no group cover")
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
        XCTAssertTrue(back.exists, "Settings had no back button")
        back.tap()
        // Changing the layout preserves the held photo, which can put the first member offscreen.
        element(in: app, "clove.grid").collectionViews.firstMatch.swipeDown()
        XCTAssertTrue(
            element(in: app, "clove.grid.photo.mmq02678").exists,
            "The expanded grid did not show a group member as its own cell")
    }

    @MainActor
    private func hideAndShowSimilarGroups(in app: XCUIApplication) {
        openSettingsFromGrid(in: app)
        setSimilarGroups(in: app, on: false)
        backToGrid(in: app)
        XCTAssertFalse(
            element(in: app, "clove.grid.group.burst-2678").exists,
            "Turning similar groups off left the grid's similar group")
        XCTAssertFalse(
            groupingActionIsVisible(in: app), "Turning similar groups off left Run again")

        openSettingsFromGrid(in: app)
        setSimilarGroups(in: app, on: true)
        backToGrid(in: app)
        element(in: app, "clove.grid").collectionViews.firstMatch.swipeDown()
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
            element(in: app, "clove.settings").exists,
            "Settings did not appear"
        )
    }

    @MainActor
    private func setSimilarGroups(in app: XCUIApplication, on: Bool) {
        let toggle = element(in: app, "clove.settings.similarGroupsEnabled")
        let window = app.windows.firstMatch.frame
        for _ in 0..<8 {
            if toggle.isHittable, toggle.frame.maxY < window.maxY - 120 { break }
            app.swipeUp()
        }
        XCTAssertTrue(toggle.exists, "Settings had no similar-groups switch")
        // A SwiftUI row toggle only flips on its switch, which sits at the trailing edge; a tap
        // in the middle of the row lands on the label.
        if switchValue(toggle) != (on ? "1" : "0") {
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
        back.tap()
        XCTAssertTrue(
            element(in: app, "clove.grid").exists,
            "Back did not return to the grid"
        )
    }

    @MainActor
    private func setGridGroupDisplay(in app: XCUIApplication, to name: String) {
        let picker = scrollToSettingsControl("clove.settings.gridGroupDisplay", in: app)
        XCTAssertTrue(picker.exists, "Settings had no grid display control")
        let option = picker.buttons[name]
        XCTAssertTrue(
            option.exists,
            "The grid display control offered no \(name) option")
        option.tap()
    }

    @MainActor
    private func scrollToSettingsControl(
        _ identifier: String, in app: XCUIApplication, swipes: Int = 6, scrollsUp: Bool = true
    ) -> XCUIElement {
        let control = element(in: app, identifier)
        for _ in 0..<swipes {
            if control.isHittable { return control }
            if scrollsUp { app.swipeUp() } else { app.swipeDown() }
        }
        return control
    }

    @MainActor
    private func element(in app: XCUIApplication, _ identifier: String) -> XCUIElement {
        element(app, identifier)
    }

    @MainActor
    private func rejectPhotosForMove(in app: XCUIApplication) {
        let first = element(in: app, "clove.grid.photo.mmq02681")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The grid did not show the first photo")
        first.press(forDuration: 1)
        let second = element(in: app, "clove.grid.photo.mmq02689")
        second.tap()

        let count = element(in: app, "clove.grid.batch.count")
        XCTAssertEqual(count.label, "2 selected")

        element(in: app, "clove.grid.batch.reject").tap()
        XCTAssertTrue(first.label.contains("Rejected"))
        XCTAssertTrue(
            second.label.contains("Rejected"), "The batch did not reject the second photo")

        element(in: app, "clove.grid.batch.done").tap()
        XCTAssertFalse(count.exists)
    }

    @MainActor
    private func checkMoveRejectsSetting(in app: XCUIApplication) {
        XCTAssertTrue(
            element(in: app, "clove.grid.moveRejects").exists,
            "The grid did not offer Move rejects with rejected photos in the folder")

        openSettingsFromGrid(in: app)
        setMoveRejects(in: app, on: false)
        backToGrid(in: app)
        XCTAssertFalse(
            element(in: app, "clove.grid.moveRejects").exists,
            "Turning Move rejects off left its grid action")

        openSettingsFromGrid(in: app)
        setMoveRejects(in: app, on: true)
        backToGrid(in: app)
        XCTAssertTrue(
            element(in: app, "clove.grid.moveRejects").exists,
            "Turning Move rejects back on did not restore its grid action")
    }

    @MainActor
    private func setMoveRejects(in app: XCUIApplication, on: Bool) {
        let toggle = scrollToSettingsControl("clove.settings.moveRejectsEnabled", in: app)
        XCTAssertTrue(toggle.exists, "Settings had no Move rejects switch")
        if switchValue(toggle) != (on ? "1" : "0") {
            toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(
            switchValue(toggle), on ? "1" : "0",
            "The Move rejects switch did not turn \(on ? "on" : "off")")
    }

}
