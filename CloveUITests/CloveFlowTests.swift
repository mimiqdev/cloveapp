import UIKit
import XCTest

/// The UI flow tests: longer paths through the real controls, backed by the in-memory library.
///
/// `mise run ui-flows` runs them; the smoke test is `CloveSmokeTests`.
final class CloveFlowTests: XCTestCase {
    /// Run on a throwaway iPad with CLOVE_SIM_DEVICE_TYPE; the default iPhone gate skips it.
    @MainActor
    func testIPadSidebarFiltersAndFullScreenDetail() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = launchSample()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .portrait
        openLibrary(app)
        let sidebar = element(app, "clove.sidebar")
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(sidebar.isHittable)
        XCTAssertTrue(element(app, "clove.sidebar.rejected").isHittable)
        XCTAssertTrue(element(app, "clove.nav.back").isHittable)
        capture("ipad-sidebar-grid-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(sidebar.isHittable)
        XCTAssertFalse(element(app, "clove.grid.filter").exists)
        let title = element(app, "clove.grid.title")
        XCTAssertEqual(title.label, "All")
        let move = element(app, "clove.grid.moveRejects")
        XCTAssertTrue(move.exists)
        XCTAssertLessThan(abs(move.frame.midY - title.frame.midY), 40)
        XCTAssertEqual(move.frame.width, 40, accuracy: 1)
        XCTAssertFalse(app.staticTexts["Analyzed"].exists)
        for theme in ["light", "dark"] {
            element(app, "clove.grid.more").tap()
            app.buttons["Settings"].tap()
            XCTAssertFalse(sidebar.exists)
            let matchSystem = app.switches["clove.settings.appearance.matchSystem"]
            if matchSystem.value as? String == "1" {
                matchSystem.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                    .withOffset(CGVector(dx: -50, dy: 0)).tap()
                XCTAssertTrue(wait(NSPredicate(format: "value == %@", "0"), matchSystem))
            }
            let tile = element(app, "clove.settings.appearance.theme.\(theme)")
            tile.tap()
            XCTAssertTrue(wait(NSPredicate(format: "isSelected == true"), tile))
            capture("ipad-settings-back-\(theme)")
            let back = element(app, "clove.nav.back")
            XCTAssertEqual(back.label, "Back")
            back.tap()
            XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
            capture("ipad-sidebar-grid-\(theme)")
        }
        element(app, "clove.sidebar.rejected").tap()
        XCTAssertTrue(waitForLabel("Rejected", title))
        XCTAssertTrue(element(app, "clove.sidebar.rejected").isSelected)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02680").exists)
        let rejected = element(app, "clove.grid.photo.mmq02679")
        XCTAssertTrue(rejected.waitForExistence(timeout: 5))
        rejected.tap()
        let detail = element(app, "clove.detail")
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        XCTAssertFalse(sidebar.exists)
        XCTAssertFalse(element(app, "clove.grid").exists)
        XCTAssertGreaterThan(detail.frame.width, app.frame.width * 0.95)
        let back = element(app, "clove.nav.back")
        XCTAssertEqual(back.label, "Back")
        capture("ipad-detail-rejected-back")
        back.tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertEqual(title.label, "Rejected")
        XCTAssertTrue(element(app, "clove.sidebar.rejected").isSelected)
        element(app, "clove.sidebar.folder.DCIM/101CAM").tap()
        XCTAssertTrue(waitForLabel("DCIM/101CAM", title))
        XCTAssertFalse(rejected.exists)
        element(app, "clove.sidebar.label.red").tap()
        XCTAssertTrue(waitForLabel("Red", title))
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02678").waitForExistence(timeout: 5))
        element(app, "clove.sidebar.all").tap()
        XCTAssertTrue(waitForLabel("All", title))
        element(app, "clove.grid").collectionViews.firstMatch.swipeUp()
        let lastPhoto = element(app, "clove.grid.photo.mmq02713")
        XCTAssertTrue(lastPhoto.isHittable)
        let previousY = lastPhoto.frame.minY
        lastPhoto.tap()
        XCTAssertTrue(detail.waitForExistence(timeout: 5))
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(sidebar.waitForExistence(timeout: 5))
        XCTAssertTrue(lastPhoto.isHittable)
        XCTAssertEqual(lastPhoto.frame.minY, previousY, accuracy: 3)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.entry").waitForExistence(timeout: 5))
    }

    @MainActor
    func testGridAndDetailControls() {
        let app = launchSample()
        openLibrary(app)
        XCTAssertFalse(element(app, "clove.grid.saveState").exists)
        let companion = element(app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(companion.waitForExistence(timeout: 5))
        XCTAssertTrue(companion.label.contains("JPEG companion"))
        XCTAssertTrue(element(app, "clove.grid.group.burst-2678").exists)
        companion.tap()
        XCTAssertTrue(element(app, "clove.detail.capsule").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.info").exists)
        XCTAssertTrue(element(app, "clove.detail.undo").exists)
    }

    @MainActor
    func testSaveFailureShowsToastAndTheFilesMarks() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_FAIL_STEMS": "2680"])
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let label = element(app, "clove.detail.capsule.label")
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        element(app, "clove.detail.labels.red").tap()
        XCTAssertTrue(app.staticTexts["Couldn't save the mark."].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLabel("Label", label))
        XCTAssertFalse(element(app, "clove.detail.saveState").exists)
        XCTAssertFalse(element(app, "clove.save.toast.action").exists)
    }

    @MainActor
    func testDriveLossDropsTheRequestedMarkAndDisablesMarking() {
        let app = launchSample([
            "CLOVE_TEST_LIBRARY_DISCONNECT_ON_WRITE": "1",
            "CLOVE_TEST_LIBRARY_WRITE_DELAY_MS": "500",
        ])
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let label = element(app, "clove.detail.capsule.label")
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        element(app, "clove.detail.labels.red").tap()
        XCTAssertTrue(waitForLabel("Not connected", element(app, "clove.detail.saveState")))
        XCTAssertFalse(element(app, "clove.save.toast").exists)
        XCTAssertEqual(label.label, "Label")
        XCTAssertFalse(label.isEnabled)
        element(app, "clove.nav.back").tap()
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02680").label.contains("Red"))
    }

    @MainActor
    func testMarkingStillAdvancesWhenTheUnmarkedFilterRemovesThePhoto() {
        let app = launchSample()
        openLibrary(app)
        element(app, "clove.grid.filter").tap()
        element(app, "clove.grid.filter.unmarked").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        let rating = element(app, "clove.detail.capsule.stars.3")
        XCTAssertTrue(rating.waitForExistence(timeout: 5))
        rating.tap()
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
    }

    @MainActor
    func testShownMarkTimingWhileWriteIsHeldPending() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_WRITE_DELAY_MS": "5000"])
        defer { app.terminate() }
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let label = element(app, "clove.detail.capsule.label")
        XCTAssertTrue(label.waitForExistence(timeout: 5))
        label.tap()
        let start = ContinuousClock.now
        element(app, "clove.detail.labels.red").tap()
        var shownLabel = label.label
        for _ in 0..<100 {
            if shownLabel == "Label, Red" { break }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
            shownLabel = label.label
        }
        let elapsed = start.duration(to: .now)
        XCTAssertEqual(shownLabel, "Label, Red")
        print(
            "Tap to shown mark, test library with a 5000 ms pending write (informational, includes XCTest input and observation): \(elapsed)"
        )
        XCTAssertFalse(element(app, "clove.detail.saveState").exists)
        XCTAssertEqual(label.label, "Label, Red")
    }

    @MainActor
    func testSelectAllIsAvailableBeforeSelectingAPhoto() {
        let app = launchSample()
        openLibrary(app)
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        element(app, "clove.grid.selectionOptions").tap()
        app.buttons["Select all"].tap()
        XCTAssertTrue(waitForLabel("36 selected", element(app, "clove.grid.batch.count")))
        XCTAssertTrue(element(app, "clove.grid.batch.stars.3").isEnabled)
    }

    @MainActor
    func testMixedBatchCanClearRatingsWithoutAnIntermediateMark() {
        let app = launchSample()
        openLibrary(app)
        let rated = element(app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(rated.waitForExistence(timeout: 5))
        rated.press(forDuration: 0.6)
        element(app, "clove.grid.photo.mmq02680").tap()
        element(app, "clove.grid.batch").press(forDuration: 0.6)
        app.buttons["Clear rating"].tap()
        XCTAssertTrue(wait(NSPredicate(format: "NOT (label CONTAINS %@)", "stars"), rated))
        XCTAssertTrue(rated.label.contains("Red"))
    }

    @MainActor
    func testDetailInfoLabelsZoomAndMarking() {
        let app = launchSample()
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let info = element(app, "clove.detail.info")
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        let navigationPreview = element(app, "clove.detail.preview")
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", navigationPreview))
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), navigationPreview))
        XCTAssertFalse(
            String(describing: navigationPreview.value).localizedCaseInsensitiveContains("loading"))
        let navigationStart = ContinuousClock.now
        navigationPreview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
        print(
            "Detail navigation swipe to next filename (informational, XCTest input included): \(navigationStart.duration(to: .now))"
        )
        navigationPreview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
        info.tap()
        XCTAssertTrue(app.staticTexts["Sample camera · 0123"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["24–70 mm"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", ":05.42")).firstMatch
                .exists)
        element(app, "clove.detail.info.done").tap()
        element(app, "clove.detail.capsule.label").tap()
        element(app, "clove.detail.labels.green").tap()
        XCTAssertFalse(element(app, "clove.detail.labels").exists)
        let preview = element(app, "clove.detail.preview")
        let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.doubleTap()
        XCTAssertTrue(waitForLabel("3 / 36 · 100%", element(app, "clove.detail.zoom")))
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        XCTAssertFalse(element(app, "clove.detail.info").exists)
        XCTAssertFalse(element(app, "clove.detail.undo").exists)
        centre.tap()
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        centre.doubleTap()
        XCTAssertTrue(info.waitForExistence(timeout: 5))
        centre.tap()
        XCTAssertTrue(waitForGone(element(app, "clove.detail.capsule")))
        centre.tap()
        XCTAssertTrue(element(app, "clove.detail.capsule").waitForExistence(timeout: 5))
        element(app, "clove.detail.capsule.stars.4").tap()
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
        XCTAssertTrue(String(describing: element(app, "clove.detail.capsule").value).contains("4"))
        let start = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        let end = start.withOffset(CGVector(dx: 0, dy: -130))
        start.press(forDuration: 0.1, thenDragTo: end)
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
    }

    @MainActor
    func testRejectedDetailGlyphWithChromeShownAndHidden() throws {
        for theme in ["light", "dark"] {
            let app = launchSample()
            openLibrary(app)
            applyComparisonTheme(theme, app)
            element(app, "clove.grid.photo.mmq02680").tap()
            let preview = element(app, "clove.detail.preview")
            XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
            let unmarkedCorner = try rejectGlyphPixels(in: preview)
            let glyph = element(app, "clove.detail.rejectGlyph")
            XCTAssertFalse(glyph.exists)
            element(app, "clove.detail.capsule.reject").tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
            XCTAssertTrue(waitForLabel("MMQ02680.ARW, Rejected", preview))
            let rejectedCorner = try rejectGlyphPixels(in: preview)
            XCTAssertNotEqual(rejectedCorner, unmarkedCorner)
            XCTAssertTrue(glyph.exists)
            let glyphFrame = glyph.frame
            capture("detail-rejected-\(theme)-chrome-shown")
            let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            centre.tap()
            XCTAssertTrue(waitForGone(element(app, "clove.detail.capsule")))
            XCTAssertTrue(glyph.exists)
            XCTAssertEqual(glyph.frame, glyphFrame)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
            capture("detail-rejected-\(theme)-chrome-hidden")
            centre.doubleTap()
            XCTAssertTrue(waitForLabel("3 / 36 · 100%", element(app, "clove.detail.zoom")))
            XCTAssertTrue(glyph.exists)
            XCTAssertEqual(glyph.frame, glyphFrame)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
            preview.swipeLeft()
            XCTAssertTrue(glyph.exists)
            XCTAssertEqual(glyph.frame, glyphFrame)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
            centre.doubleTap()
            centre.tap()
            XCTAssertTrue(element(app, "clove.detail.capsule.reject").waitForExistence(timeout: 5))
            element(app, "clove.detail.capsule.reject").tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
            XCTAssertTrue(waitForLabel("MMQ02680.ARW", preview))
            XCTAssertFalse(glyph.exists)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), unmarkedCorner)
            app.terminate()
        }
    }

    /// Sample the opaque centre of the 22 pt glyph, inset 8 pt in the stage.
    @MainActor
    private func rejectGlyphPixels(in preview: XCUIElement) throws -> Data {
        let screenshot = XCUIScreen.main.screenshot().image
        let region = CGRect(
            x: preview.frame.maxX - 25, y: preview.frame.minY + 13, width: 12, height: 12
        )
        .applying(CGAffineTransform(scaleX: screenshot.scale, y: screenshot.scale))
        let pixels = try XCTUnwrap(screenshot.cgImage?.cropping(to: region))
        return try XCTUnwrap(UIImage(cgImage: pixels).pngData())
    }

    @MainActor
    func testCameraDisplayChoiceAndDetailZoom() {
        let app = launchSample()
        openLibrary(app)
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        let display = element(app, "clove.settings.photoDisplayMode")
        for _ in 0..<6 {
            if display.exists && display.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(display.isHittable)
        display.tap()
        app.buttons["Camera preview"].tap()
        XCTAssertTrue(
            String(describing: display.value).contains("Camera preview")
                || display.label.contains("Camera preview"))
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(waitForLabel("3 / 36 · 100%", element(app, "clove.detail.zoom")))
    }

    @MainActor
    func testDisconnectedFolderBanner() {
        let disconnected = launchSample(["CLOVE_TEST_LIBRARY_LOCATION_LOSS": "drive"])
        openLibrary(disconnected)
        XCTAssertEqual(element(disconnected, "clove.grid.saveState").label, "Not connected")
        XCTAssertTrue(disconnected.staticTexts["The drive disconnected."].exists)
        XCTAssertTrue(element(disconnected, "clove.grid.saveState.failure.action").exists)
        element(disconnected, "clove.grid.group.burst-2678").tap()
        XCTAssertTrue(element(disconnected, "clove.detail").waitForExistence(timeout: 5))
        XCTAssertTrue(element(disconnected, "clove.detail.saveStatus.failure.action").exists)
    }

    /// A stack uses detail; one undo restores every photo rejected by the finishing pill.
    @MainActor
    func testStackOpensDetailAndFinishingUndoRestoresUnmarkedTogether() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        openLibrary(app)
        element(app, "clove.grid.group.burst-2678").tap()
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", element(app, "clove.detail.fileName")))
        XCTAssertTrue(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        XCTAssertFalse(element(app, "clove.detail.rejectUnmarked").exists)
        element(app, "clove.detail.capsule.label").tap()
        element(app, "clove.detail.labels.green").tap()
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.group.burst-2678").tap()
        XCTAssertTrue(waitForLabel("MMQ02679.ARW", element(app, "clove.detail.fileName")))
        let pill = element(app, "clove.detail.rejectUnmarked")
        XCTAssertEqual(pill.label, "Reject 2 unmarked")
        pill.tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
        XCTAssertFalse(pill.exists)
        element(app, "clove.detail.undo").tap()
        XCTAssertTrue(waitForLabel("MMQ02679.ARW", element(app, "clove.detail.fileName")))
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, "Reject 2 unmarked")
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02678").label.contains("Green"))
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02679").label.contains("Rejected"))
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02681").label.contains("Rejected"))
        XCTAssertFalse(element(app, "clove.detail.undo").exists)
    }

    @MainActor
    func testFinishingPillRequiresAKeepInTheVisibleGroup() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        openLibrary(app)
        element(app, "clove.grid.filter").tap()
        element(app, "clove.grid.filter.unmarked").tap()
        element(app, "clove.grid.group.burst-2678").tap()
        element(app, "clove.detail.capsule.label").tap()
        element(app, "clove.detail.labels.green").tap()
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", element(app, "clove.detail.fileName")))
        XCTAssertFalse(element(app, "clove.detail.rejectUnmarked").exists)
    }

    @MainActor
    func testGroupZoomKeepsTheCropUntilLeavingItsMembers() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        openLibrary(app)
        element(app, "clove.grid.group.burst-2678").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(waitForGone(element(app, "clove.detail.info")))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertTrue(waitForLabel("MMQ02679.ARW", element(app, "clove.detail.fileName")))
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertFalse(element(app, "clove.detail.info").exists)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
        XCTAssertTrue(element(app, "clove.detail.info").waitForExistence(timeout: 5))
    }

    @MainActor
    func testMoveRejectsConfirmsAndReportsFilesLeftInPlace() {
        let app = launchSample([
            "CLOVE_TEST_LIBRARY_MOVE_FAIL_STEM_SUFFIX": "5",
            "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
        ])
        openLibrary(app)
        element(app, "clove.grid.moveRejects").tap()
        XCTAssertTrue(
            waitForLabel("Move 2 rejected photos", element(app, "clove.moves.confirmation")))
        element(app, "clove.moves.expand").tap()
        element(app, "clove.moves.keep.mmq02679").tap()
        element(app, "clove.moves.confirm").tap()
        XCTAssertTrue(element(app, "clove.moves.toast.action").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.moves.toast.action").label, "Undo")
        element(app, "clove.moves.toast.secondaryAction").tap()
        XCTAssertTrue(element(app, "clove.moves.details.row.mmq02685").waitForExistence(timeout: 5))
        element(app, "clove.moves.details.done").tap()
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02685").label.contains("Rejected"))
    }

    @MainActor
    func testAMoveThatMovedNothingOffersDetailsWithoutUndo() {
        let app = launchSample([
            "CLOVE_TEST_LIBRARY_MOVE_FAIL_STEM_SUFFIX": "",
            "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
        ])
        openLibrary(app)
        element(app, "clove.grid.moveRejects").tap()
        element(app, "clove.moves.confirm").tap()
        let toast = element(app, "clove.moves.toast")
        XCTAssertTrue(toast.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.moves.toast.action").exists)
        let details = toast.buttons["clove.moves.toast.secondaryAction"]
        XCTAssertTrue(details.exists)
        details.tap()
        XCTAssertTrue(element(app, "clove.moves.details.sheet").waitForExistence(timeout: 5))
    }

    @MainActor
    func testDesignGalleryShowsSharedControls() {
        let app = launchSample(["CLOVE_DESIGN_GALLERY": "1"])
        XCTAssertTrue(element(app, "clove.design.gallery").waitForExistence(timeout: 10))
        XCTAssertTrue(element(app, "clove.mark.capsule").exists)
        XCTAssertTrue(element(app, "clove.mark.starBar").exists)
        element(app, "clove.design.gallery.theme.nord").tap()
        XCTAssertTrue(element(app, "clove.design.gallery.theme.nord").isSelected)
    }

    @MainActor
    func testCaptureDetailGroupWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_DETAIL_GROUP"] == "1")
        for theme in ["light", "dark"] {
            let app = launchSample()
            openLibrary(app)
            applyComparisonTheme(theme, app)
            element(app, "clove.grid.group.burst-2678").tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
            let pill = element(app, "clove.detail.rejectUnmarked")
            XCTAssertTrue(pill.waitForExistence(timeout: 5))
            XCTAssertTrue(pill.isHittable)
            XCTAssertLessThanOrEqual(
                pill.frame.maxY, element(app, "clove.detail.capsule").frame.minY)
            capture("detail-expanded-pill-\(theme)")
            app.terminate()
        }
    }

    /// Explicit visual comparison only; the everyday flow run skips this matrix.
    @MainActor
    func testCaptureGroupAndMoveReferencesWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_GROUP_MOVES"] == "1")
        for theme in ["light", "dark", "nord"] {
            let app = launchSample([
                "CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked",
                "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
            ])
            openLibrary(app)
            applyComparisonTheme(theme, app)
            element(app, "clove.grid.group.burst-2678").tap()
            element(app, "clove.detail.capsule.stars.3").tap()
            XCTAssertTrue(waitForLabel("MMQ02679.ARW", element(app, "clove.detail.fileName")))
            XCTAssertTrue(element(app, "clove.detail.rejectUnmarked").waitForExistence(timeout: 5))
            capture("detail-expanded-group-\(theme)")
            element(app, "clove.detail.rejectUnmarked").tap()
            XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
            element(app, "clove.nav.back").tap()
            element(app, "clove.grid.moveRejects").tap()
            XCTAssertTrue(element(app, "clove.moves.expand").waitForExistence(timeout: 5))
            capture("move-confirm-\(theme)")
            element(app, "clove.moves.expand").tap()
            element(app, "clove.moves.keep.mmq02685").tap()
            XCTAssertTrue(waitForLabel("2 of 3 will move", element(app, "clove.moves.partial")))
            capture("move-keeps-\(theme)")
            element(app, "clove.moves.confirm").tap()
            XCTAssertTrue(element(app, "clove.moves.toast.action").waitForExistence(timeout: 5))
            capture("move-done-\(theme)")
            app.terminate()

            let partial = launchSample([
                "CLOVE_TEST_LIBRARY_MOVE_FAIL_STEM_SUFFIX": "5",
                "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
            ])
            openLibrary(partial)
            applyComparisonTheme(theme, partial)
            element(partial, "clove.grid.moveRejects").tap()
            element(partial, "clove.moves.confirm").tap()
            XCTAssertTrue(partial.staticTexts["1 couldn't be moved"].waitForExistence(timeout: 5))
            capture("move-partial-\(theme)")
            element(partial, "clove.moves.toast.secondaryAction").tap()
            XCTAssertTrue(
                element(partial, "clove.moves.details.sheet").waitForExistence(timeout: 5))
            capture("move-details-\(theme)")
            partial.terminate()
        }
    }

    /// Opt-in visual evidence for the shared stack and badge in the three reference themes.
    @MainActor
    func testCaptureStackReferencesWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_STACKS"] == "1")
        for theme in ["light", "dark", "nord"] {
            let app = launchSample()
            openLibrary(app)
            applyComparisonTheme(theme, app)
            capture("stacks-expanded-\(theme)")
            element(app, "clove.grid.more").tap()
            app.buttons["Settings"].tap()
            chooseCollapsedGrid(app)
            element(app, "clove.nav.back").tap()
            capture("stacks-collapsed-\(theme)")
            element(app, "clove.grid.photo.mmq02682").tap()
            XCTAssertTrue(element(app, "clove.detail.filmstrip").waitForExistence(timeout: 5))
            capture("stacks-filmstrip-\(theme)")
            app.terminate()
        }
    }

    @MainActor
    private func applyComparisonTheme(_ theme: String, _ app: XCUIApplication) {
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        chooseTheme(theme, app)
        element(app, "clove.nav.back").tap()
    }

    /// Explicit screenshot run only. The normal flow run skips this comparison matrix.
    @MainActor
    func testCaptureDesignReferencesWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_DESIGN"] == "1")
        if XCUIScreen.main.screenshot().image.size.width > 700 {
            let app = launchSample(["CLOVE_DESIGN_GALLERY": "1"])
            XCTAssertTrue(element(app, "clove.design.gallery").waitForExistence(timeout: 10))
            capture("gallery-ipad-centred")
            app.swipeUp()
            capture("gallery-ipad-lower")
            return
        }
        let themes =
            ProcessInfo.processInfo.environment["CLOVE_CAPTURE_THEMES"]?
            .split(separator: ",").map(String.init) ?? ["light", "dark", "nord"]
        for theme in themes {
            let app = launchSample()
            openLibrary(app)
            element(app, "clove.grid.more").tap()
            app.buttons["Settings"].tap()
            chooseTheme(theme, app)
            chooseCollapsedGrid(app)
            element(app, "clove.nav.back").tap()
            capture("grid-\(theme)")
            element(app, "clove.grid.filter").tap()
            element(app, "clove.grid.filter.unmarked").tap()
            element(app, "clove.grid.filter").tap()
            XCTAssertTrue(element(app, "clove.grid.filter.all").waitForExistence(timeout: 5))
            capture("grid-filter-\(theme)")
            element(app, "clove.grid.filter.all").tap()
            element(app, "clove.grid.more").tap()
            XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 5))
            capture("grid-more-\(theme)")
            // The native menu overlaps the title. A tap to its left dismisses it.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.6)).tap()
            let photo = element(app, "clove.grid.photo.mmq02680")
            photo.press(forDuration: 0.6)
            XCTAssertTrue(element(app, "clove.grid.batch.done").waitForExistence(timeout: 5))
            capture("grid-select-\(theme)")
            element(app, "clove.grid.batch.done").tap()
            photo.tap()
            XCTAssertTrue(element(app, "clove.detail.capsule").waitForExistence(timeout: 5))
            capture("detail-\(theme)")
            element(app, "clove.detail.capsule.label").tap()
            XCTAssertTrue(element(app, "clove.detail.labels.green").waitForExistence(timeout: 5))
            capture("detail-labels-\(theme)")
            element(app, "clove.detail.labels.green").tap()
            element(app, "clove.detail.info").tap()
            XCTAssertTrue(app.staticTexts["Sample camera · 0123"].waitForExistence(timeout: 5))
            capture("detail-info-\(theme)")
            element(app, "clove.detail.info.done").tap()
            let preview = element(app, "clove.detail.preview")
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
            XCTAssertTrue(waitForGone(element(app, "clove.detail.capsule")))
            capture("detail-zoom-\(theme)")
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
            element(app, "clove.detail.capsule.reject").tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
            XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
            capture("detail-rejected-\(theme)")
            element(app, "clove.nav.back").tap()
            app.swipeUp()
            XCTAssertTrue(element(app, "clove.grid.photo.mmq02700").waitForExistence(timeout: 5))
            capture("grid-no-preview-\(theme)")
            app.terminate()
        }
        for stage in ["reading", "grouping"] {
            let app = launchSample(["CLOVE_TEST_LIBRARY_OPENING": stage])
            openLibrary(app)
            capture("grid-opening-\(stage)")
            XCTAssertFalse(element(app, "clove.grid.moveRejects").exists)
            element(app, "clove.grid.photo.mmq02680").tap()
            XCTAssertTrue(element(app, "clove.detail.capsule").waitForExistence(timeout: 5))
            app.terminate()
        }
        let app = launchSample(["CLOVE_TEST_LIBRARY_LOCATION_LOSS": "drive"])
        openLibrary(app)
        capture("grid-disconnected")
    }

    @MainActor
    func testCaptureInformationAndEmptyOpeningWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_DESIGN"] == "1")
        let app = launchSample()
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        element(app, "clove.detail.info").tap()
        XCTAssertTrue(app.staticTexts["Sample camera · 0123"].waitForExistence(timeout: 5))
        capture("detail-info-compact")
        element(app, "clove.detail.info.done").tap()
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(
            element(app, "clove.settings.appearance.theme.light").waitForExistence(timeout: 5))
        capture("theme-tiles")
        app.terminate()
        let opening = launchSample(["CLOVE_TEST_LIBRARY_OPENING": "empty"])
        openLibrary(opening)
        XCTAssertTrue(opening.collectionViews.firstMatch.exists)
        XCTAssertFalse(element(opening, "clove.grid.moveRejects").exists)
        capture("grid-opening-before-first-photo")
    }

    @MainActor
    private func launchSample(_ environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["CLOVE_TEST_LIBRARY": "1"].merging(environment) { _, new in new }
        app.launch()
        let root =
            environment["CLOVE_DESIGN_GALLERY"] == "1" ? "clove.design.gallery" : "clove.root"
        XCTAssertTrue(element(app, root).waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    private func openLibrary(_ app: XCUIApplication) {
        let open = element(app, "clove.entry.openFolder")
        if open.exists { open.tap() }
        if element(app, "clove.detail").exists { element(app, "clove.nav.back").tap() }
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 5))
    }

    @MainActor
    private func chooseCollapsedGrid(_ app: XCUIApplication) {
        let control = element(app, "clove.settings.gridGroupDisplay")
        for _ in 0..<8 {
            if control.exists && control.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(control.exists)
        control.buttons["Collapsed"].tap()
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    private func waitForLabel(_ label: String, _ target: XCUIElement) -> Bool {
        wait(NSPredicate(format: "label == %@", label), target)
    }

    @MainActor
    private func waitForGone(_ target: XCUIElement) -> Bool {
        wait(NSPredicate(format: "exists == false"), target)
    }

    @MainActor
    private func wait(_ predicate: NSPredicate, _ target: XCUIElement) -> Bool {
        XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: target)], timeout: 5)
            == .completed
    }

    @MainActor
    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
