import XCTest

/// Restores the original browsing safety net, adapted only to the designed controls and glyphs.
extension CloveFlowTests {
    /// The Appearance setting keeps independent mode and family choices across a relaunch and
    /// preserves each axis when the other changes.
    ///
    /// This launch uses the app's own settings storage rather than the sample library, because
    /// the check is that the next launch reads what this one stored. The teardown puts System +
    /// Default back on, so other tests see the default appearance.
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
        openSettingsCategory("clove.settings.category.appearance", in: app)
        _ = scrollToSettingsControl(
            "clove.settings.appearance.mode", in: app, scrollsUp: false)

        let modePicker = element(in: app, "clove.settings.appearance.mode")
        XCTAssertTrue(modePicker.exists, "Settings had no appearance mode picker")
        XCTAssertTrue(
            modePicker.buttons["System"].isSelected,
            "System mode did not start selected")
        XCTAssertTrue(
            app.buttons["clove.settings.appearance.family.default"].isSelected,
            "Default family did not start selected")

        // Choosing a non-default family preserves System mode.
        let catppuccin = app.buttons["clove.settings.appearance.family.catppuccin"]
        XCTAssertTrue(catppuccin.exists, "The theme picker had no Catppuccin tile")
        catppuccin.tap()
        XCTAssertTrue(catppuccin.isSelected, "Catppuccin did not become selected")
        XCTAssertTrue(
            modePicker.buttons["System"].isSelected,
            "Selecting a non-default family unexpectedly changed System mode")

        // Changing mode preserves the chosen family.
        setAppearanceMode(in: app, to: "Dark")
        XCTAssertTrue(
            catppuccin.isSelected,
            "Changing mode unexpectedly reset the selected family")

        app.terminate()
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The relaunched Clove did not appear")
        openSettings(in: app)
        let appearanceRow = element(in: app, "clove.settings.category.appearance")
        if appearanceRow.exists, let summary = appearanceRow.value as? String, !summary.isEmpty {
            XCTAssertEqual(summary, "Dark · Catppuccin")
        }
        openSettingsCategory("clove.settings.category.appearance", in: app)
        let relaunchedMode = element(in: app, "clove.settings.appearance.mode")
        XCTAssertTrue(
            relaunchedMode.buttons["Dark"].isSelected,
            "The relaunch lost the Dark mode")
        XCTAssertTrue(
            app.buttons["clove.settings.appearance.family.catppuccin"].isSelected,
            "The relaunch lost the Catppuccin family")
    }

    /// System mode + a non-default family stays on System + that family across live system
    /// appearance transitions without falling back to Default, while explicit Light/Dark modes
    /// ignore system appearance transitions, and Reset restores System · Default.
    @MainActor
    func testSystemModeWithNonDefaultFamilyTracksSystemAppearance() throws {
        let initialDeviceAppearance = XCUIDevice.shared.appearance
        addTeardownBlock { @MainActor in
            XCUIDevice.shared.appearance = initialDeviceAppearance
            Self.restoreAppearance()
        }

        XCUIDevice.shared.appearance = .light
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            element(in: app, "clove.root").waitForExistence(timeout: 30),
            "The Clove root view did not appear")
        openSettings(in: app)
        let appearanceRow = element(in: app, "clove.settings.category.appearance")
        if appearanceRow.exists, let summary = appearanceRow.value as? String, !summary.isEmpty {
            XCTAssertEqual(summary, "System · Default")
        }
        openSettingsCategory("clove.settings.category.appearance", in: app)

        let nord = app.buttons["clove.settings.appearance.family.nord"]
        XCTAssertTrue(nord.waitForExistence(timeout: 5), "Nord family tile missing")
        nord.tap()
        XCTAssertTrue(nord.isSelected)
        XCTAssertTrue(
            element(in: app, "clove.settings.appearance.mode").buttons["System"].isSelected)

        let lightSystemShot = XCUIScreen.main.screenshot().pngRepresentation

        XCUIDevice.shared.appearance = .dark
        let modeControl = element(in: app, "clove.settings.appearance.mode")
        XCTAssertTrue(
            wait(
                NSPredicate { _, _ in
                    XCUIScreen.main.screenshot().pngRepresentation != lightSystemShot
                },
                modeControl),
            "System + Nord did not update UI when device switched from Light to Dark")
        XCTAssertTrue(modeControl.buttons["System"].isSelected)
        XCTAssertTrue(nord.isSelected, "System appearance change fell back away from Nord")

        // Explicit Light ignores dark system appearance; explicit Dark stays dark even on light system.
        setAppearanceMode(in: app, to: "Light")
        XCTAssertTrue(nord.isSelected)
        let forcedLightOnDarkSystem = XCUIScreen.main.screenshot().pngRepresentation
        XCUIDevice.shared.appearance = .light
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(modeControl.buttons["Light"].isSelected)
        XCTAssertTrue(nord.isSelected)

        setAppearanceMode(in: app, to: "Dark")
        RunLoop.current.run(until: Date().addingTimeInterval(0.3))
        XCTAssertTrue(nord.isSelected)
        let forcedDarkOnLightSystem = XCUIScreen.main.screenshot().pngRepresentation
        XCTAssertNotEqual(forcedLightOnDarkSystem, forcedDarkOnLightSystem)

        // Navigate back to compact Settings home if needed and Reset to defaults.
        let backToSettings = app.navigationBars.buttons["Settings"]
        if backToSettings.exists, !element(in: app, "clove.settings.reset").exists {
            backToSettings.tap()
        }
        let reset = scrollToSettingsControl("clove.settings.reset", in: app)
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()
        let confirm = app.alerts["Reset settings to defaults?"].buttons["Reset"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(
            wait(
                NSPredicate { _, _ in
                    let value =
                        self.element(in: app, "clove.settings.category.appearance").value
                        as? String
                    return value == "System · Default"
                        || self.element(in: app, "clove.settings.appearance.family.default")
                            .isSelected
                },
                app))
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
        let appearanceCategory = app.descendants(matching: .any)
            .matching(identifier: "clove.settings.category.appearance").firstMatch
        if appearanceCategory.exists {
            appearanceCategory.tap()
        }
        let modeControl = app.descendants(matching: .any)["clove.settings.appearance.mode"]
        guard modeControl.waitForExistence(timeout: 5) else { return }
        let systemButton = modeControl.buttons["System"]
        if systemButton.exists, !systemButton.isSelected {
            systemButton.tap()
        }
        let defaultFamily = app.buttons["clove.settings.appearance.family.default"]
        if defaultFamily.exists, !defaultFamily.isSelected {
            defaultFamily.tap()
        }
    }

    /// Selects one of the segmented appearance modes (`Light`, `Dark`, or `System`).
    @MainActor
    func setAppearanceMode(in app: XCUIApplication, to modeTitle: String) {
        let picker = element(in: app, "clove.settings.appearance.mode")
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "Settings had no appearance mode picker")
        let option = picker.buttons[modeTitle]
        XCTAssertTrue(option.exists, "Appearance mode picker had no \(modeTitle) option")
        if !option.isSelected {
            option.tap()
        }
        XCTAssertTrue(option.isSelected, "Appearance mode did not switch to \(modeTitle)")
    }

    /// Selects a theme family and optional mode from a resolved palette or family identifier.
    @MainActor
    func chooseTheme(_ theme: String, _ app: XCUIApplication) {
        openSettingsCategory("clove.settings.category.appearance", in: app)
        let (modeTitle, familyID) = Self.modeAndFamily(for: theme)
        setAppearanceMode(in: app, to: modeTitle)
        let tile = element(in: app, "clove.settings.appearance.family.\(familyID)")
        XCTAssertTrue(tile.exists, "Theme family tile missing for \(familyID)")
        tile.tap()
        XCTAssertTrue(tile.isSelected, "Theme family \(familyID) did not become selected")
    }

    private static func modeAndFamily(for theme: String) -> (mode: String, family: String) {
        switch theme {
        case "light": ("Light", "default")
        case "dark": ("Dark", "default")
        case "catppuccin-latte": ("Light", "catppuccin")
        case "catppuccin-mocha": ("Dark", "catppuccin")
        case "darkroom-light": ("Light", "darkroom")
        case "darkroom": ("Dark", "darkroom")
        case "night-light": ("Light", "night")
        case "night": ("Dark", "night")
        case "nord-light": ("Light", "nord")
        case "nord": ("Dark", "nord")
        case "gruvbox-light": ("Light", "gruvbox")
        case "gruvbox": ("Dark", "gruvbox")
        default: ("Dark", theme)
        }
    }

    /// The browsing path through the real controls, from Entry to the grid, detail, and
    /// the settings that change the grid.
    ///
    /// Steps other tests or TLA+/unit suites cover are not repeated here:
    /// - double-tap zoom, culling swipes, and filmstrip navigation/group focus: dedicated gesture and
    ///   filmstrip tests (`testDetailInfoLabelsZoomAndMarking`,
    ///   `testFilmstripAnchorsVisibleGroupAndCentersOffscreenNavigation`,
    ///   `testZoomedRatingSwipeModesAndPinchSafety`);
    /// - the group's finishing actions and Undo: `testFinishingPillNeverResizesTheStage`,
    ///   `PhotoActionsTests`;
    /// - a batch rating with a failed write: `testFinishingPillAndSaveFailureToastStayUsable`,
    ///   `PhotoActionsTests`;
    /// - Move rejects with a keep and a failure: `testMoveRejectsConfirmsAndReportsFilesLeftInPlace`,
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
        returnToGrid(in: app)
        openSettings(in: app)
        checkSimplifiedGroupingSettings(in: app)
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
        XCTAssertTrue(element(in: app, "clove.settings.category.appearance").exists)
        XCTAssertTrue(element(in: app, "clove.settings.category.culling").exists)
        XCTAssertTrue(element(in: app, "clove.settings.category.browsing").exists)
        XCTAssertTrue(element(in: app, "clove.settings.category.photoDisplay").exists)
        XCTAssertTrue(element(in: app, "clove.settings.category.moveRejects").exists)
        XCTAssertTrue(element(in: app, "clove.settings.reset").exists)
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
        XCTAssertFalse(element(in: app, "clove.grid.saveState").exists)
        let group = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(group.waitForExistence(timeout: 10), "The grid did not show burst-2678 stack")
        let groupLabel = group.label
        XCTAssertTrue(
            groupLabel.contains("Similar group of 3 photos"),
            "The stack lost its group count: \(groupLabel)")
        XCTAssertFalse(
            element(in: app, "clove.grid.photo.mmq02679").exists,
            "Grouped mode should collapse group members on the grid")

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
        let first = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(first.waitForExistence(timeout: 10), "The grid did not show the first group")
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
            fileName.label == "MMQ02678.ARW",
            "The detail view did not open on the representative photo")
        XCTAssertTrue(
            element(in: app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5),
            "Opening a grid stack did not enter Group Focus")
        if !element(in: app, "clove.detail.rail").exists {
            let capsule = element(in: app, "clove.detail.capsule")
            XCTAssertTrue(capsule.exists)
            XCTAssertEqual(capsule.frame.width, 168, accuracy: 1)
            XCTAssertEqual(capsule.frame.height, 48, accuracy: 1)
        }
        XCTAssertTrue(element(in: app, "clove.detail.info").exists)
        XCTAssertTrue(element(in: app, "clove.detail.undo").exists)

        let marks = detailMarksControl(in: app).value as? String
        XCTAssertTrue(
            marks?.contains("5 stars") == true,
            "The detail view did not show the saved rating: \(String(describing: marks))"
        )
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
        let group = element(in: app, "clove.grid.group.burst-2678")
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertTrue(
            group.label.contains("Similar group of 3 photos"),
            "The grid cover lost its group count: \(group.label)"
        )
    }

    @MainActor
    func openSettings(in app: XCUIApplication) {
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
    func openSettingsCategory(_ categoryIdentifier: String, in app: XCUIApplication) {
        let category = element(in: app, categoryIdentifier)
        if !category.exists {
            let backToHome = app.navigationBars.buttons["Settings"]
            if backToHome.exists { backToHome.tap() }
        }
        for _ in 0..<4 where !category.isHittable { app.swipeDown() }
        XCTAssertTrue(
            category.waitForExistence(timeout: 5),
            "Settings did not show category \(categoryIdentifier)"
        )
        category.tap()
    }

    @MainActor
    private func checkSimplifiedGroupingSettings(in app: XCUIApplication) {
        openSettingsCategory("clove.settings.category.browsing", in: app)
        XCTAssertFalse(
            element(in: app, "clove.settings.gridGroupDisplay").exists,
            "Redundant Grid display setting should be removed")
        backToGrid(in: app)
    }

    @MainActor
    private func hideAndShowSimilarGroups(in app: XCUIApplication) {
        openSettingsFromGrid(in: app)
        openSettingsCategory("clove.settings.category.browsing", in: app)
        setSimilarGroups(in: app, on: false)
        backToGrid(in: app)
        XCTAssertFalse(
            element(in: app, "clove.grid.group.burst-2678").exists,
            "Turning similar groups off left the grid's similar group")
        XCTAssertFalse(
            groupingActionIsVisible(in: app), "Turning similar groups off left Run again")
        let ratedLabel = element(in: app, "clove.grid.photo.mmq02678").label
        XCTAssertTrue(
            ratedLabel.contains("5 stars"),
            "The flat grid did not show the member's saved rating: \(ratedLabel)")
        let rejectedLabel = element(in: app, "clove.grid.photo.mmq02679").label
        XCTAssertTrue(
            rejectedLabel.contains("Rejected"),
            "The flat grid did not show the member's Reject: \(rejectedLabel)")
        XCTAssertFalse(
            rejectedLabel.contains("2 stars"), "A rejected photo kept its stars: \(rejectedLabel)")
        XCTAssertFalse(
            rejectedLabel.contains("-1"), "A rejected photo read its rating: \(rejectedLabel)")

        openSettingsFromGrid(in: app)
        openSettingsCategory("clove.settings.category.browsing", in: app)
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
    func setSimilarGroups(in app: XCUIApplication, on: Bool) {
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
    func scrollToSettingsControl(
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
        let first = element(in: app, "clove.grid.photo.mmq02682")
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
        openSettingsCategory("clove.settings.category.moveRejects", in: app)
        setMoveRejects(in: app, on: false)
        backToGrid(in: app)
        XCTAssertFalse(
            element(in: app, "clove.grid.moveRejects").exists,
            "Turning Move rejects off left its grid action")

        openSettingsFromGrid(in: app)
        openSettingsCategory("clove.settings.category.moveRejects", in: app)
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

    @MainActor @objc
    func testSettingsCategoriesSubpagesValidationAndResetConfirmation() {
        let app = launchSample()
        openSettings(in: app)

        // Nested Rating scale under Culling & marking enforces at least one level enabled.
        openSettingsCategory("clove.settings.category.culling", in: app)
        let ratingScaleLink = scrollToSettingsControl("clove.settings.ratingScale", in: app)
        XCTAssertTrue(ratingScaleLink.exists)
        ratingScaleLink.tap()

        for level in 1...4 {
            let toggle = app.switches["clove.settings.rating.\(level)"]
            XCTAssertTrue(toggle.waitForExistence(timeout: 5))
            if switchValue(toggle) == "1" {
                toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
            }
            XCTAssertEqual(switchValue(toggle), "0")
        }
        let lastRating = app.switches["clove.settings.rating.5"]
        XCTAssertEqual(switchValue(lastRating), "1")
        XCTAssertFalse(lastRating.isEnabled, "The last remaining rating level stayed enabled")

        let backToCulling = app.navigationBars.buttons["Culling & marking"]
        if backToCulling.exists {
            backToCulling.tap()
        } else {
            app.navigationBars.buttons["Settings"].tap()
            openSettingsCategory("clove.settings.category.culling", in: app)
        }

        // Nested Auto-advance destination: Stay disables trigger toggles without clearing choices.
        let destinationLink = scrollToSettingsControl(
            "clove.settings.autoAdvanceDestination", in: app)
        XCTAssertTrue(destinationLink.waitForExistence(timeout: 5))
        destinationLink.tap()
        let stayRow = element(in: app, "clove.settings.autoAdvance.stay")
        XCTAssertTrue(stayRow.waitForExistence(timeout: 5))
        stayRow.tap()
        XCTAssertTrue(stayRow.isSelected)

        if app.navigationBars.buttons["Culling & marking"].exists {
            app.navigationBars.buttons["Culling & marking"].tap()
        } else {
            app.navigationBars.buttons["Settings"].tap()
            openSettingsCategory("clove.settings.category.culling", in: app)
        }
        let ratingsAdvance = scrollToSettingsControl("clove.settings.autoAdvanceRating", in: app)
        XCTAssertFalse(ratingsAdvance.isEnabled)

        // Move rejects folder validation shows inline error on invalid folder name.
        openSettingsCategory("clove.settings.category.moveRejects", in: app)
        let folderField = scrollToSettingsControl("clove.settings.rejectsFolderName", in: app)
        XCTAssertTrue(folderField.waitForExistence(timeout: 5))
        folderField.tap()
        folderField.typeText("/")
        XCTAssertTrue(
            element(in: app, "clove.settings.rejectsFolderNameProblem").waitForExistence(timeout: 5)
        )

        // Reset confirmation cancels cleanly and resets preferences only on Reset.
        let backHome = app.navigationBars.buttons["Settings"]
        if backHome.exists { backHome.tap() }
        let reset = scrollToSettingsControl("clove.settings.reset", in: app)
        XCTAssertTrue(reset.waitForExistence(timeout: 5))
        reset.tap()

        let alert = app.alerts["Reset settings to defaults?"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Cancel"].tap()
        openSettingsCategory("clove.settings.category.culling", in: app)
        XCTAssertFalse(
            scrollToSettingsControl("clove.settings.autoAdvanceRating", in: app).isEnabled)

        if app.navigationBars.buttons["Settings"].exists {
            app.navigationBars.buttons["Settings"].tap()
        }
        scrollToSettingsControl("clove.settings.reset", in: app).tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["Reset"].tap()

        openSettingsCategory("clove.settings.category.culling", in: app)
        XCTAssertTrue(
            scrollToSettingsControl("clove.settings.autoAdvanceRating", in: app).isEnabled)
        openSettingsCategory("clove.settings.category.moveRejects", in: app)
        XCTAssertFalse(element(in: app, "clove.settings.rejectsFolderNameProblem").exists)
    }

    /// Switching language in Settings updates Settings, Grid, Detail, and Info sheet live
    /// without restarting the process, and restores English when returned to Follow System.
    @MainActor @objc
    func testLiveLanguageSwitchingAcrossSettingsGridAndDetail() {
        let app = launchSample()

        // 1. Verify Language category sits immediately after Appearance and starts on Follow System.
        openSettings(in: app)
        let appearanceCategory = element(in: app, "clove.settings.category.appearance")
        let languageCategory = element(in: app, "clove.settings.category.language")
        XCTAssertTrue(appearanceCategory.waitForExistence(timeout: 5))
        XCTAssertTrue(languageCategory.waitForExistence(timeout: 5))
        XCTAssertLessThan(appearanceCategory.frame.minY, languageCategory.frame.minY)

        languageCategory.tap()
        let systemOption = element(in: app, "clove.settings.language.system")
        let hansOption = element(in: app, "clove.settings.language.simplifiedChinese")
        let hantOption = element(in: app, "clove.settings.language.traditionalChinese")
        XCTAssertTrue(systemOption.waitForExistence(timeout: 5))
        XCTAssertTrue(systemOption.isSelected)
        XCTAssertEqual(systemOption.label, "Follow System")

        // 2. Switch to Simplified Chinese live.
        hansOption.tap()
        XCTAssertTrue(hansOption.isSelected)
        XCTAssertEqual(systemOption.label, "跟随系统")

        returnFromSettingsCategoryToRoot(in: app)
        openLibrary(app)

        let filterButton = element(in: app, "clove.grid.filter")
        if filterButton.exists {
            XCTAssertEqual(filterButton.label, "筛选")
        } else {
            XCTAssertEqual(element(in: app, "clove.grid.title").label, "全部")
        }
        XCTAssertEqual(element(in: app, "clove.grid.moveRejects").label, "整理淘汰片")

        element(in: app, "clove.grid.photo.mmq02680").tap()
        XCTAssertTrue(element(in: app, "clove.detail").waitForExistence(timeout: 10))
        XCTAssertEqual(element(in: app, "clove.detail.info").label, "信息")
        let capsuleReject = element(in: app, "clove.detail.capsule.reject")
        if capsuleReject.exists {
            XCTAssertEqual(capsuleReject.label, "淘汰")
        }
        element(in: app, "clove.detail.info").tap()
        XCTAssertTrue(element(in: app, "clove.detail.info.sheet").waitForExistence(timeout: 5))
        XCTAssertEqual(element(in: app, "clove.detail.info.done").label, "完成")
        XCTAssertTrue(app.staticTexts["文件"].waitForExistence(timeout: 5))
        element(in: app, "clove.detail.info.done").tap()

        element(in: app, "clove.nav.back").tap()
        XCTAssertTrue(element(in: app, "clove.grid").waitForExistence(timeout: 5))

        // 3. Switch to Traditional Chinese live from Grid -> Settings.
        element(in: app, "clove.grid.more").tap()
        app.buttons["设置"].tap()
        XCTAssertTrue(element(in: app, "clove.settings").waitForExistence(timeout: 5))
        openSettingsCategory("clove.settings.category.language", in: app)

        XCTAssertTrue(hantOption.waitForExistence(timeout: 5))
        hantOption.tap()
        XCTAssertTrue(hantOption.isSelected)
        XCTAssertEqual(systemOption.label, "跟隨系統")

        returnFromSettingsCategoryToGrid(in: app)
        if filterButton.exists {
            XCTAssertEqual(filterButton.label, "篩選")
        } else {
            XCTAssertEqual(element(in: app, "clove.grid.title").label, "全部")
        }
        XCTAssertEqual(element(in: app, "clove.grid.moveRejects").label, "整理淘汰片")

        element(in: app, "clove.grid.photo.mmq02680").tap()
        XCTAssertTrue(element(in: app, "clove.detail").waitForExistence(timeout: 10))
        XCTAssertEqual(element(in: app, "clove.detail.info").label, "資訊")
        element(in: app, "clove.detail.info").tap()
        XCTAssertTrue(element(in: app, "clove.detail.info.sheet").waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["檔案"].waitForExistence(timeout: 5))
        element(in: app, "clove.detail.info.done").tap()

        element(in: app, "clove.nav.back").tap()
        XCTAssertTrue(element(in: app, "clove.grid").waitForExistence(timeout: 5))

        // 4. Return to Follow System and verify English returns live.
        element(in: app, "clove.grid.more").tap()
        app.buttons["設定"].tap()
        XCTAssertTrue(element(in: app, "clove.settings").waitForExistence(timeout: 5))
        openSettingsCategory("clove.settings.category.language", in: app)

        XCTAssertTrue(systemOption.waitForExistence(timeout: 5))
        systemOption.tap()
        XCTAssertTrue(systemOption.isSelected)
        XCTAssertEqual(systemOption.label, "Follow System")

        returnFromSettingsCategoryToGrid(in: app)
        if filterButton.exists {
            XCTAssertEqual(filterButton.label, "Filter")
        } else {
            XCTAssertEqual(element(in: app, "clove.grid.title").label, "All")
        }
        XCTAssertEqual(element(in: app, "clove.grid.moveRejects").label, "Move rejects")
    }

    @MainActor
    private func returnFromSettingsCategoryToRoot(in app: XCUIApplication) {
        if !element(in: app, "clove.nav.back").exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(element(in: app, "clove.entry.openFolder").waitForExistence(timeout: 5))
    }

    @MainActor
    private func returnFromSettingsCategoryToGrid(in app: XCUIApplication) {
        if !element(in: app, "clove.nav.back").exists {
            app.navigationBars.buttons.element(boundBy: 0).tap()
        }
        let back = element(in: app, "clove.nav.back")
        XCTAssertTrue(back.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(element(in: app, "clove.grid").waitForExistence(timeout: 5))
    }

}
