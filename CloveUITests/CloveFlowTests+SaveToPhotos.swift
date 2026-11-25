import UIKit
import XCTest

extension CloveFlowTests {
    @MainActor
    func testSaveToPhotosAllEligibleSavesAndPreservesSelection() {
        let app = launchSample([
            "CLOVE_TEST_LIBRARY_RASTER_SAMPLES": "1",
            "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
        ])
        defer { app.terminate() }
        openLibrary(app)
        turnOffSimilarGroups(in: app)
        enterGridSelectionMode(in: app)

        // Scroll to the appended JPEG, HEIF, and RAW+HEIF sample photos at the bottom.
        let grid = element(app, "clove.grid").collectionViews.firstMatch
        let heifTile = element(app, "clove.grid.photo.mmq02715")
        for _ in 0..<6 where !heifTile.isHittable {
            grid.swipeUp()
        }
        for stem in ["mmq02714", "mmq02715", "mmq02716"] {
            let tile = element(app, "clove.grid.photo.\(stem)")
            if !tile.isHittable { grid.swipeUp() }
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            tile.tap()
        }
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")

        tapSaveToPhotosAction(in: app)

        let toast = element(app, "clove.photos.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.staticTexts["Saved 3 photos to Photos"].waitForExistence(timeout: 5))

        let batchBar = element(app, "clove.grid.batch")
        XCTAssertTrue(batchBar.exists)
        XCTAssertLessThanOrEqual(toast.frame.maxY, batchBar.frame.minY + 1)
        XCTAssertTrue(element(app, "clove.grid.batch.done").exists)
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")
    }

    @MainActor
    func testSaveToPhotosRawOnlyAlertAndMixedConfirmationAndCancel() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)
        turnOffSimilarGroups(in: app)
        enterGridSelectionMode(in: app)

        // Two RAW-only photos trigger the informational alert without starting a Photos save.
        for stem in ["mmq02678", "mmq02679"] {
            let tile = element(app, "clove.grid.photo.\(stem)")
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            tile.tap()
        }
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        tapSaveToPhotosAction(in: app)

        let noEligibleAlert = app.alerts["No JPEG or HEIF to save"]
        XCTAssertTrue(noEligibleAlert.waitForExistence(timeout: 5))
        noEligibleAlert.buttons["clove.photos.noEligible.ok"].firstMatch.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), noEligibleAlert))
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")
        XCTAssertFalse(element(app, "clove.photos.toast").exists)

        // Add one RAW+JPEG photo -> mixed confirmation alert, Cancel preserves state, Save exports 1.
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")

        tapSaveToPhotosAction(in: app)

        let confirmAlert = app.alerts["Save 1 photo to Photos?"]
        XCTAssertTrue(confirmAlert.waitForExistence(timeout: 5))
        confirmAlert.buttons["clove.photos.confirm.cancel"].firstMatch.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), confirmAlert))
        XCTAssertFalse(element(app, "clove.photos.toast").exists)
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")

        tapSaveToPhotosAction(in: app)
        XCTAssertTrue(confirmAlert.waitForExistence(timeout: 5))
        let saveConfirmButton = confirmAlert.buttons["clove.photos.confirm.save"].firstMatch
        XCTAssertEqual(saveConfirmButton.label, "Save 1")
        saveConfirmButton.tap()

        let toast = element(app, "clove.photos.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(
            toast.staticTexts["Saved 1 photo to Photos · 2 RAW skipped"].waitForExistence(
                timeout: 5))
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")
    }

    @MainActor
    func testSaveToPhotosFilteredSelectionScopesToVisibleTargets() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone)
        let app = launchSample(["CLOVE_TEST_LIBRARY_KEEP_TOAST": "1"])
        defer { app.terminate() }
        openLibrary(app)
        turnOffSimilarGroups(in: app)
        enterGridSelectionMode(in: app)

        // Reject only the eligible RAW+JPEG photo (mmq02680), then also select RAW-only mmq02678.
        let eligible = element(app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(eligible.waitForExistence(timeout: 5))
        eligible.tap()
        element(app, "clove.grid.batch.reject").tap()

        let rawOnly = element(app, "clove.grid.photo.mmq02678")
        rawOnly.tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        // Filter to Rejected: only mmq02680 is visible, mmq02678 stays hidden by filter.
        let filterButton = element(app, "clove.grid.filter")
        XCTAssertTrue(filterButton.waitForExistence(timeout: 5))
        filterButton.tap()
        element(app, "clove.grid.filter.rejected").tap()

        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
        let hiddenCount = element(app, "clove.grid.batch.hiddenCount")
        XCTAssertTrue(hiddenCount.waitForExistence(timeout: 5))
        XCTAssertEqual(hiddenCount.label, "1 hidden by filter")

        // Saving only considers visible targets -> immediate save with no mixed-selection alert.
        tapSaveToPhotosAction(in: app)

        let toast = element(app, "clove.photos.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(toast.staticTexts["Saved 1 photo to Photos"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.alerts.firstMatch.exists)
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
        XCTAssertEqual(hiddenCount.label, "1 hidden by filter")
    }

    @MainActor
    func testSaveToPhotosShowsPermissionAndWriteFailureToastsAndDisablesWhenLocationLost() {
        // 1. Permission denied toast preserves selection.
        do {
            let app = launchSample([
                "CLOVE_TEST_LIBRARY_PHOTOS_AUTHORIZATION": "denied",
                "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
            ])
            defer { app.terminate() }
            openLibrary(app)
            enterGridSelectionMode(in: app)

            let eligible = element(app, "clove.grid.photo.mmq02680")
            XCTAssertTrue(eligible.waitForExistence(timeout: 5))
            eligible.tap()
            tapSaveToPhotosAction(in: app)

            let toast = element(app, "clove.photos.toast")
            XCTAssertTrue(toast.waitForExistence(timeout: 5))
            XCTAssertTrue(
                toast.staticTexts["Allow Photos access in Settings to save photos."]
                    .waitForExistence(timeout: 5))
            XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
        }

        // 2. Write failure toast preserves selection.
        do {
            let app = launchSample([
                "CLOVE_TEST_LIBRARY_PHOTOS_SAVE_ERROR": "write",
                "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
            ])
            defer { app.terminate() }
            openLibrary(app)
            enterGridSelectionMode(in: app)

            let eligible = element(app, "clove.grid.photo.mmq02680")
            XCTAssertTrue(eligible.waitForExistence(timeout: 5))
            eligible.tap()
            tapSaveToPhotosAction(in: app)

            let toast = element(app, "clove.photos.toast")
            XCTAssertTrue(toast.waitForExistence(timeout: 5))
            XCTAssertTrue(
                toast.staticTexts["Couldn't save to Photos."].waitForExistence(timeout: 5))
            XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
        }

        // 3. Disconnected folder disables Actions (both Save to Photos and Rename).
        do {
            let app = launchSample(["CLOVE_TEST_LIBRARY_LOCATION_LOSS": "drive"])
            defer { app.terminate() }
            openLibrary(app)
            enterGridSelectionMode(in: app)

            // FolderSaveBanner overlays Row 1 when location is lost; pick an eligible cell clear of
            // both the banner at the top and the batch bar at the bottom.
            let grid = element(app, "clove.grid").collectionViews.firstMatch
            let batchBar = element(app, "clove.grid.batch")
            let eligible = element(app, "clove.grid.photo.mmq02695")
            for _ in 0..<4
            where !eligible.exists || !eligible.isHittable
                || eligible.frame.maxY >= batchBar.frame.minY - 8
            {
                grid.swipeUp()
            }
            XCTAssertTrue(eligible.waitForExistence(timeout: 5))
            eligible.tap()
            XCTAssertEqual(element(app, "clove.grid.batch.count").label, "1 selected")
            XCTAssertFalse(element(app, "clove.grid.batch.actions").isEnabled)
        }
    }

    @MainActor
    func testSaveToPhotosConfirmationSheetWhenSettingEnabled() {
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

        enterGridSelectionMode(in: app)

        // All RAW-only: sheet opens with Save 0 Photos disabled and Cancel leaves state clean.
        for stem in ["mmq02678", "mmq02679"] {
            let tile = element(app, "clove.grid.photo.\(stem)")
            XCTAssertTrue(tile.waitForExistence(timeout: 5))
            tile.tap()
        }
        tapSaveToPhotosAction(in: app)

        let sheet = element(app, "clove.photos.sheet")
        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(sheet.navigationBars["Save to Photos"].exists)
        let readyRow = element(app, "clove.photos.sheet.ready")
        XCTAssertTrue(readyRow.label.contains("Ready to save"))
        XCTAssertTrue(readyRow.label.contains("0 photos"))
        let skippedRow = element(app, "clove.photos.sheet.skipped")
        XCTAssertTrue(skippedRow.label.contains("RAW only · skipped"))
        XCTAssertTrue(skippedRow.label.contains("2 photos"))
        let confirmButton = element(app, "clove.photos.sheet.confirm")
        XCTAssertEqual(confirmButton.label, "Save 0 Photos")
        XCTAssertFalse(confirmButton.isEnabled)

        element(app, "clove.photos.sheet.cancel").tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), sheet))
        XCTAssertFalse(element(app, "clove.photos.toast").exists)

        // Add eligible RAW+JPEG: sheet shows Ready to save (1 photo), Save 1 Photo exports & shows toast.
        element(app, "clove.grid.photo.mmq02680").tap()
        tapSaveToPhotosAction(in: app)

        XCTAssertTrue(sheet.waitForExistence(timeout: 5))
        XCTAssertTrue(readyRow.label.contains("1 photo"))
        XCTAssertTrue(skippedRow.label.contains("2 photos"))
        XCTAssertEqual(confirmButton.label, "Save 1 Photo")
        XCTAssertTrue(confirmButton.isEnabled)
        confirmButton.tap()

        let toast = element(app, "clove.photos.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertTrue(
            toast.staticTexts["Saved 1 photo to Photos · 2 RAW skipped"].waitForExistence(
                timeout: 5))
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "3 selected")
    }

    @MainActor
    private func turnOffSimilarGroups(in app: XCUIApplication) {
        openSettings(in: app)
        openSettingsCategory("clove.settings.category.browsing", in: app)
        setSimilarGroups(in: app, on: false)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 5))
    }

    @MainActor
    private func enterGridSelectionMode(in app: XCUIApplication) {
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        XCTAssertTrue(element(app, "clove.grid.batch").waitForExistence(timeout: 5))
    }

    @MainActor
    private func tapSaveToPhotosAction(in app: XCUIApplication) {
        let actions = element(app, "clove.grid.batch.actions")
        XCTAssertTrue(actions.waitForExistence(timeout: 5))
        XCTAssertTrue(actions.isEnabled)
        actions.tap()
        let saveItem = element(app, "clove.grid.batch.saveToPhotos")
        XCTAssertTrue(saveItem.waitForExistence(timeout: 5))
        saveItem.tap()
    }
}
