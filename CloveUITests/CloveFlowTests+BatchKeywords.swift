import UIKit
import XCTest

extension CloveFlowTests {
    @MainActor
    func testBatchKeywordsAddSuggestRemoveDetailInfoAndUndo() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)
        disableSimilarGroupsForBatchKeywords(app)

        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        XCTAssertFalse(element(app, "clove.grid.batch.actions").isEnabled)

        element(app, "clove.grid.photo.mmq02680").tap()
        element(app, "clove.grid.photo.mmq02681").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        openBatchKeywordsSheet(app)
        let applyButton = element(app, "clove.keywords.apply")
        XCTAssertFalse(applyButton.isEnabled)

        // Canceling leaves selection and marks untouched.
        element(app, "clove.keywords.cancel").tap()
        XCTAssertTrue(element(app, "clove.grid.batch").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        // Add comma-separated keywords via text input + Apply.
        openBatchKeywordsSheet(app)
        let input = app.textFields["clove.keywords.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Harbour, Dawn")
        XCTAssertTrue(wait(NSPredicate(format: "isEnabled == true"), applyButton, timeout: 5))
        applyButton.tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"), element(app, "clove.keywords.sheet"),
                timeout: 5))

        // Switch selection to {mmq02680, mmq02683} for mixed common/partial/suggestions state.
        element(app, "clove.grid.photo.mmq02681").tap()
        element(app, "clove.grid.photo.mmq02683").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        openBatchKeywordsSheet(app)
        let mixed = element(app, "clove.keywords.mixed")
        XCTAssertTrue(mixed.waitForExistence(timeout: 5))
        XCTAssertTrue(mixed.label.contains("Harbour"))
        XCTAssertTrue(mixed.label.contains("Dawn"))

        // Tap folder suggestion to add Harbour to both selected photos, then remove it in place.
        let harbourSuggestion = element(app, "clove.keywords.suggestion.Harbour")
        XCTAssertTrue(harbourSuggestion.waitForExistence(timeout: 5))
        harbourSuggestion.tap()

        let removeHarbour = element(app, "clove.keywords.remove.Harbour")
        XCTAssertTrue(removeHarbour.waitForExistence(timeout: 5))
        XCTAssertFalse(harbourSuggestion.exists)
        XCTAssertTrue(element(app, "clove.keywords.done").waitForExistence(timeout: 5))

        removeHarbour.tap()
        XCTAssertTrue(harbourSuggestion.waitForExistence(timeout: 5))
        element(app, "clove.keywords.done").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"), element(app, "clove.keywords.sheet"),
                timeout: 5))

        // Exit select mode, inspect mmq02680 in Detail Info, then Undo the batch removal.
        element(app, "clove.grid.batch.done").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")

        element(app, "clove.detail.info").tap()
        XCTAssertTrue(element(app, "clove.detail.info.sheet").waitForExistence(timeout: 5))
        let keywordsRow = element(app, "clove.detail.info.keywords")
        XCTAssertTrue(keywordsRow.waitForExistence(timeout: 5))
        XCTAssertTrue(keywordsRow.label.contains("Dawn"))
        XCTAssertFalse(keywordsRow.label.contains("Harbour"))
        let marksRow = element(app, "clove.detail.info.marks")
        XCTAssertTrue(marksRow.waitForExistence(timeout: 5))
        XCTAssertTrue(marksRow.label.contains("1 keyword"))
        element(app, "clove.detail.info.done").tap()
        XCTAssertTrue(
            wait(NSPredicate(format: "exists == false"), element(app, "clove.detail.info.sheet")))

        XCTAssertFalse(element(app, "clove.detail.undo").exists)
        XCTAssertFalse(element(app, "clove.detail.undoToast").exists)

        // Return to Grid and re-add Harbour in place to confirm reversible batch keyword editing.
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        openBatchKeywordsSheet(app)
        XCTAssertTrue(harbourSuggestion.waitForExistence(timeout: 5))
        harbourSuggestion.tap()
        XCTAssertTrue(removeHarbour.waitForExistence(timeout: 5))
        element(app, "clove.keywords.done").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"), element(app, "clove.keywords.sheet"),
                timeout: 5))
        element(app, "clove.grid.batch.done").tap()
        element(app, "clove.grid.photo.mmq02680").tap()

        element(app, "clove.detail.info").tap()
        XCTAssertTrue(element(app, "clove.detail.info.sheet").waitForExistence(timeout: 5))
        let restoredRow = element(app, "clove.detail.info.keywords")
        XCTAssertTrue(restoredRow.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredRow.label.contains("Harbour"))
        XCTAssertTrue(restoredRow.label.contains("Dawn"))
        let restoredMarksRow = element(app, "clove.detail.info.marks")
        XCTAssertTrue(restoredMarksRow.waitForExistence(timeout: 5))
        XCTAssertTrue(restoredMarksRow.label.contains("2 keywords"))
        element(app, "clove.detail.info.done").tap()
    }

    @MainActor
    func testBatchKeywordsScopesToVisibleTargetsWhenFilterHidesSelection() throws {
        try XCTSkipUnless(
            UIDevice.current.userInterfaceIdiom == .phone,
            "Header Filter menu in select mode is compact-width iPhone behavior")
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)
        disableSimilarGroupsForBatchKeywords(app)

        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()

        // Ensure both are non-rejected first, then reject only mmq02678 while keeping both selected.
        element(app, "clove.grid.photo.mmq02678").tap()
        element(app, "clove.grid.photo.mmq02679").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")
        element(app, "clove.grid.batch.rating").tap()
        XCTAssertTrue(element(app, "clove.grid.batch.stars").waitForExistence(timeout: 5))
        element(app, "clove.grid.batch.stars.4").tap()
        element(app, "clove.grid.photo.mmq02679").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
        element(app, "clove.grid.batch.reject").tap()
        element(app, "clove.grid.photo.mmq02679").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        let filterButton = element(app, "clove.grid.filter")
        filterButton.tap()
        element(app, "clove.grid.filter.rejected").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
        XCTAssertEqual(element(app, "clove.grid.batch.hiddenCount").label, "1 hidden by filter")

        openBatchKeywordsSheet(app)
        let summary = element(app, "clove.keywords.summary")
        XCTAssertTrue(summary.waitForExistence(timeout: 5))
        XCTAssertTrue(summary.label.contains("1 selected"))
        XCTAssertTrue(summary.label.contains("1 hidden by filter"))

        let input = app.textFields["clove.keywords.input"]
        input.tap()
        input.typeText("VisibleOnly")
        element(app, "clove.keywords.apply").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"), element(app, "clove.keywords.sheet"),
                timeout: 5))

        filterButton.tap()
        element(app, "clove.grid.filter.all").tap()
        element(app, "clove.grid.batch.done").tap()

        // Hidden-by-filter mmq02679 stayed untouched.
        element(app, "clove.grid.photo.mmq02679").tap()
        element(app, "clove.detail.info").tap()
        XCTAssertTrue(element(app, "clove.detail.info.sheet").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.detail.info.keywords").exists)
        element(app, "clove.detail.info.done").tap()
        element(app, "clove.nav.back").tap()

        // Visible mmq02678 received VisibleOnly.
        element(app, "clove.grid.photo.mmq02678").tap()
        element(app, "clove.detail.info").tap()
        XCTAssertTrue(element(app, "clove.detail.info.sheet").waitForExistence(timeout: 5))
        let keywordsRow = element(app, "clove.detail.info.keywords")
        XCTAssertTrue(keywordsRow.waitForExistence(timeout: 5))
        XCTAssertTrue(keywordsRow.label.contains("VisibleOnly"))
        element(app, "clove.detail.info.done").tap()
    }

    @MainActor
    func testBatchKeywordsStagedConfirmationSheetWhenSettingEnabled() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)

        openSettings(in: app)
        openSettingsCategory("clove.settings.category.culling", in: app)
        let confirmToggle = scrollToSettingsControl("clove.settings.confirmBatchActions", in: app)
        XCTAssertTrue(confirmToggle.waitForExistence(timeout: 5))
        if (confirmToggle.value as? String) != "1" {
            confirmToggle.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap()
        }
        XCTAssertEqual(confirmToggle.value as? String, "1")

        openSettingsCategory("clove.settings.category.browsing", in: app)
        setSimilarGroups(in: app, on: false)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 5))

        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        element(app, "clove.grid.photo.mmq02681").tap()

        openBatchKeywordsSheet(app)
        let sheet = element(app, "clove.keywords.sheet")
        XCTAssertTrue(sheet.navigationBars["Add Keywords"].exists)
        let confirmButton = element(app, "clove.keywords.confirm")
        XCTAssertTrue(confirmButton.waitForExistence(timeout: 5))
        XCTAssertEqual(confirmButton.label, "Add to 2 Photos")
        XCTAssertFalse(confirmButton.isEnabled)

        // Stage typed keywords in memory without dismissing or writing, then Cancel discards them.
        let input = app.textFields["clove.keywords.input"]
        XCTAssertTrue(input.waitForExistence(timeout: 5))
        input.tap()
        input.typeText("Harbour, Dawn")
        element(app, "clove.keywords.apply").tap()

        XCTAssertTrue(element(app, "clove.keywords.staged.Harbour").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.keywords.staged.Dawn").waitForExistence(timeout: 5))
        XCTAssertTrue(confirmButton.isEnabled)
        element(app, "clove.keywords.cancel").tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))

        // Reopen, stage again, and confirm via Add to 2 Photos.
        openBatchKeywordsSheet(app)
        let input2 = app.textFields["clove.keywords.input"]
        XCTAssertTrue(input2.waitForExistence(timeout: 5))
        input2.tap()
        input2.typeText("Harbour, Dawn")
        element(app, "clove.keywords.apply").tap()
        XCTAssertTrue(element(app, "clove.keywords.staged.Harbour").waitForExistence(timeout: 5))
        XCTAssertTrue(wait(NSPredicate(format: "isEnabled == true"), confirmButton, timeout: 5))
        confirmButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))

        // Switch selection to {mmq02680, mmq02683}, verify Recent chip stages/unstages without writing until Confirm.
        element(app, "clove.grid.photo.mmq02681").tap()
        element(app, "clove.grid.photo.mmq02683").tap()
        openBatchKeywordsSheet(app)

        let recentChip = element(app, "clove.keywords.suggestion.Harbour")
        XCTAssertTrue(recentChip.waitForExistence(timeout: 5))
        recentChip.tap()
        let stagedHarbour = element(app, "clove.keywords.staged.Harbour")
        XCTAssertTrue(stagedHarbour.waitForExistence(timeout: 5))
        XCTAssertTrue(confirmButton.isEnabled)

        stagedHarbour.tap()
        XCTAssertTrue(recentChip.waitForExistence(timeout: 5))
        XCTAssertFalse(confirmButton.isEnabled)

        recentChip.tap()
        XCTAssertTrue(wait(NSPredicate(format: "isEnabled == true"), confirmButton, timeout: 5))
        confirmButton.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))

        // Verify mmq02683 received Harbour in Detail Info and Detail keeps no permanent Undo.
        element(app, "clove.grid.batch.done").tap()
        element(app, "clove.grid.photo.mmq02683").tap()
        element(app, "clove.detail.info").tap()
        XCTAssertTrue(element(app, "clove.detail.info.sheet").waitForExistence(timeout: 5))
        let keywordsRow = element(app, "clove.detail.info.keywords")
        XCTAssertTrue(keywordsRow.waitForExistence(timeout: 5))
        XCTAssertTrue(keywordsRow.label.contains("Harbour"))
        element(app, "clove.detail.info.done").tap()
        XCTAssertTrue(
            wait(NSPredicate(format: "exists == false"), element(app, "clove.detail.info.sheet")))

        XCTAssertFalse(element(app, "clove.detail.undo").exists)
        XCTAssertFalse(element(app, "clove.detail.undoToast").exists)
    }

    @MainActor
    private func disableSimilarGroupsForBatchKeywords(_ app: XCUIApplication) {
        openSettings(in: app)
        openSettingsCategory("clove.settings.category.browsing", in: app)
        setSimilarGroups(in: app, on: false)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 5))
    }

    @MainActor
    private func openBatchKeywordsSheet(_ app: XCUIApplication) {
        let actions = element(app, "clove.grid.batch.actions")
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.isEnabled)
        actions.tap()
        let item = element(app, "clove.grid.batch.keywords")
        XCTAssertTrue(item.waitForExistence(timeout: 5))
        item.tap()
        XCTAssertTrue(element(app, "clove.keywords.sheet").waitForExistence(timeout: 5))
    }
}
