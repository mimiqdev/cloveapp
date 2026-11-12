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
        XCTAssertTrue(sidebar.exists)
        XCTAssertTrue(element(app, "clove.sidebar.rejected").isHittable)
        XCTAssertTrue(element(app, "clove.nav.back").isHittable)
        capture("ipad-sidebar-grid-portrait")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(element(app, "clove.sidebar.rejected").isHittable)
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
                XCTAssertEqual(matchSystem.value as? String, "0")
            }
            let tile = element(app, "clove.settings.appearance.theme.\(theme)")
            tile.tap()
            XCTAssertTrue(tile.isSelected)
            capture("ipad-settings-back-\(theme)")
            let back = element(app, "clove.nav.back")
            XCTAssertEqual(back.label, "Back")
            back.tap()
            XCTAssertTrue(sidebar.exists)
            capture("ipad-sidebar-grid-\(theme)")
        }
        element(app, "clove.sidebar.rejected").tap()
        XCTAssertEqual(title.label, "Rejected")
        XCTAssertTrue(element(app, "clove.sidebar.rejected").isSelected)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02680").exists)
        let rejected = element(app, "clove.grid.photo.mmq02679")
        rejected.tap()
        let detail = element(app, "clove.detail")
        XCTAssertTrue(detail.exists)
        XCTAssertFalse(sidebar.exists)
        XCTAssertFalse(element(app, "clove.grid").exists)
        XCTAssertGreaterThan(detail.frame.width, app.frame.width * 0.95)
        let back = element(app, "clove.nav.back")
        XCTAssertEqual(back.label, "Back")
        capture("ipad-detail-rejected-back")
        back.tap()
        XCTAssertTrue(sidebar.exists)
        XCTAssertEqual(title.label, "Rejected")
        XCTAssertTrue(element(app, "clove.sidebar.rejected").isSelected)
        element(app, "clove.sidebar.folder.DCIM/101CAM").tap()
        XCTAssertEqual(title.label, "DCIM/101CAM")
        XCTAssertFalse(rejected.exists)
        element(app, "clove.sidebar.label.red").tap()
        XCTAssertEqual(title.label, "Red")
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02678").exists)
        element(app, "clove.sidebar.all").tap()
        XCTAssertEqual(title.label, "All")
        element(app, "clove.grid").collectionViews.firstMatch.swipeUp()
        let lastPhoto = element(app, "clove.grid.photo.mmq02713")
        XCTAssertTrue(lastPhoto.isHittable)
        let previousY = lastPhoto.frame.minY
        lastPhoto.tap()
        XCTAssertTrue(detail.exists)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(sidebar.exists)
        XCTAssertTrue(lastPhoto.isHittable)
        XCTAssertEqual(lastPhoto.frame.minY, previousY, accuracy: 3)
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.entry").exists)
    }

    /// Rail input and chrome share the detail actions; screenshots use only the sample library.
    @MainActor
    func testIPadDetailRailMarkingAndChrome() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = launchSample()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        openLibrary(app)
        prepareRailComparison(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let rail = element(app, "clove.detail.rail")
        let stars = element(app, "clove.detail.rail.stars.3")
        let reject = element(app, "clove.detail.rail.reject")
        let green = element(app, "clove.detail.rail.label.green")
        let preview = element(app, "clove.detail.preview")
        let strip = element(app, "clove.detail.filmstrip")
        XCTAssertTrue(rail.exists)
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertEqual(rail.frame.width, 96, accuracy: 1)
        XCTAssertLessThanOrEqual(strip.frame.maxX, rail.frame.minX + 1)
        XCTAssertEqual(element(app, "clove.detail.info").frame.width, 40, accuracy: 1)
        stars.tap()
        XCTAssertTrue(stars.isSelected)
        stars.tap()
        XCTAssertFalse(stars.isSelected)
        green.tap()
        XCTAssertTrue(green.isSelected)
        XCTAssertFalse(element(app, "clove.detail.labels").exists)
        green.tap()
        XCTAssertFalse(green.isSelected)
        let bar = element(app, "clove.detail.rail.stars")
        let bottom = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        let middle = bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        bottom.press(forDuration: 0.1, thenDragTo: middle)
        XCTAssertTrue(stars.isSelected)
        // A drag back to the same rating keeps it; a tap clears it.
        bottom.press(forDuration: 0.1, thenDragTo: middle)
        XCTAssertTrue(stars.isSelected)
        middle.press(forDuration: 0.1, thenDragTo: middle.withOffset(CGVector(dx: 0, dy: -6)))
        XCTAssertTrue(stars.isSelected)
        green.tap()
        capture("ipad-detail-rail-light")
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(stars.isSelected)
        XCTAssertTrue(green.isSelected)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        XCUIDevice.shared.orientation = .landscapeLeft
        let stageFrame = preview.frame
        let railFrame = rail.frame
        let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.tap()
        XCTAssertFalse(strip.exists)
        XCTAssertTrue(rail.isHittable)
        XCTAssertEqual(preview.frame, stageFrame)
        XCTAssertEqual(rail.frame, railFrame)
        XCTAssertFalse(element(app, "clove.detail.info").exists)
        centre.tap()
        XCTAssertTrue(strip.exists)
        centre.doubleTap()
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "3 / 36 · 100%")
        XCTAssertFalse(strip.exists)
        XCTAssertTrue(rail.isHittable)
        XCTAssertEqual(preview.frame, stageFrame)
        centre.doubleTap()
        XCTAssertTrue(strip.exists)
        reject.tap()
        XCTAssertEqual(reject.label, "Rejected")
        XCTAssertTrue(element(app, "clove.detail.rejectGlyph").exists)
        XCTAssertFalse(stars.isSelected)
        XCTAssertFalse(green.isSelected)
        XCTAssertLessThan(element(app, "clove.detail.rejectGlyph").frame.maxX, rail.frame.minX)
        capture("ipad-detail-rail-rejected")
        centre.tap()
        XCTAssertFalse(strip.exists)
        XCTAssertTrue(element(app, "clove.detail.rejectGlyph").exists)
        XCTAssertTrue(reject.isHittable)
        centre.tap()
        reject.tap()
        XCTAssertEqual(reject.label, "Reject")
        XCTAssertFalse(element(app, "clove.detail.rejectGlyph").exists)
        let start = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.55))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -130)))
        XCTAssertTrue(String(describing: rail.value).contains("stars"))
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        chooseRailTheme("dark", app)
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertTrue(rail.exists)
        capture("ipad-detail-rail-dark")
        app.terminate()
        checkDisabledRail()
    }

    @MainActor
    private func prepareRailComparison(_ app: XCUIApplication) {
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        chooseRailTheme("light", app)
        turnOffAutoAdvance(app)
        element(app, "clove.nav.back").tap()
    }

    /// Turns the settle that follows a mark off, on the open Settings screen, so a test reads the
    /// marks it set instead of a photo it navigated to.
    @MainActor
    private func turnOffAutoAdvance(_ app: XCUIApplication) {
        let advance = app.switches["clove.settings.autoAdvanceEnabled"]
        for _ in 0..<5 {
            if advance.isHittable { break }
            app.swipeUp()
        }
        if advance.value as? String == "1" {
            advance.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -50, dy: 0)).tap()
        }
        XCTAssertEqual(advance.value as? String, "0")
    }

    @MainActor
    private func chooseRailTheme(_ theme: String, _ app: XCUIApplication) {
        let matchSystem = app.switches["clove.settings.appearance.matchSystem"]
        if matchSystem.value as? String == "1" {
            matchSystem.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -50, dy: 0)).tap()
            XCTAssertEqual(matchSystem.value as? String, "0")
        }
        let tile = element(app, "clove.settings.appearance.theme.\(theme)")
        tile.tap()
        XCTAssertTrue(tile.isSelected)
    }

    @MainActor
    private func checkDisabledRail() {
        let disconnected = launchSample(["CLOVE_TEST_LIBRARY_LOCATION_LOSS": "location"])
        defer { disconnected.terminate() }
        openLibrary(disconnected)
        element(disconnected, "clove.grid.photo.mmq02680").tap()
        let rail = element(disconnected, "clove.detail.rail")
        XCTAssertTrue(rail.exists)
        XCTAssertFalse(element(disconnected, "clove.detail.rail.stars.3").isEnabled)
        XCTAssertFalse(element(disconnected, "clove.detail.rail.reject").isEnabled)
        XCTAssertFalse(element(disconnected, "clove.detail.rail.label.green").isEnabled)
        let marks = rail.value as? String
        let bar = element(disconnected, "clove.detail.rail.stars")
        bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)).press(
            forDuration: 0.1,
            thenDragTo: bar.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        XCTAssertEqual(rail.value as? String, marks)
    }

    @MainActor
    func testGridAndDetailControls() {
        let app = launchSample()
        openLibrary(app)
        XCTAssertFalse(element(app, "clove.grid.saveState").exists)
        let companion = element(app, "clove.grid.photo.mmq02680")
        XCTAssertTrue(companion.label.contains("JPEG companion"))
        XCTAssertTrue(element(app, "clove.grid.group.burst-2678").exists)
        companion.tap()
        XCTAssertTrue(element(app, "clove.detail.capsule").exists)
        XCTAssertTrue(element(app, "clove.detail.info").exists)
        XCTAssertTrue(element(app, "clove.detail.undo").exists)
    }

    /// Hardware keys mark and navigate through the marking path the capsule uses (PRD P0-06).
    @MainActor
    func testDetailHardwareKeysMarkAndNavigate() {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        turnOffAutoAdvance(app)
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        let capsule = element(app, "clove.detail.capsule")
        let fileName = element(app, "clove.detail.fileName")
        XCTAssertEqual(capsule.value as? String, "Unmarked")
        app.typeKey("3", modifierFlags: [])
        XCTAssertEqual(capsule.value as? String, "3 stars")
        app.typeKey("x", modifierFlags: [])
        XCTAssertEqual(capsule.value as? String, "Rejected")
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertEqual(fileName.label, "MMQ02681.ARW")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(capsule.value as? String, "3 stars")
        element(app, "clove.detail.info").tap()
        element(app, "clove.detail.info.done").tap()
        app.typeKey("0", modifierFlags: [])
        XCTAssertEqual(capsule.value as? String, "Unmarked")
    }

    @MainActor
    func testSaveFailureShowsToastAndTheFilesMarks() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_FAIL_STEMS": "2680"])
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let label = element(app, "clove.detail.capsule.label")
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
        label.tap()
        let start = ContinuousClock.now
        element(app, "clove.detail.labels.red").tap()
        let shownLabel = label.label
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
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "36 selected")
        XCTAssertTrue(element(app, "clove.grid.batch.stars.3").isEnabled)
    }

    @MainActor
    func testMixedBatchCanClearRatingsWithoutAnIntermediateMark() {
        let app = launchSample()
        openLibrary(app)
        let rated = element(app, "clove.grid.photo.mmq02678")
        rated.press(forDuration: 0.6)
        element(app, "clove.grid.photo.mmq02680").tap()
        element(app, "clove.grid.batch").press(forDuration: 0.6)
        app.buttons["Clear rating"].tap()
        let clearedLabel = rated.label
        XCTAssertFalse(clearedLabel.contains("stars"))
        XCTAssertTrue(clearedLabel.contains("Red"))
    }

    @MainActor
    func testDetailInfoLabelsZoomAndMarking() {
        let app = launchSample()
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let info = element(app, "clove.detail.info")
        XCTAssertTrue(info.exists)
        let navigationPreview = element(app, "clove.detail.preview")
        let fileName = element(app, "clove.detail.fileName")
        let capsule = element(app, "clove.detail.capsule")
        XCTAssertEqual(navigationPreview.label, "MMQ02680.ARW")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), navigationPreview))
        XCTAssertFalse(
            String(describing: navigationPreview.value).localizedCaseInsensitiveContains("loading"))
        let navigationStart = ContinuousClock.now
        navigationPreview.swipeLeft()
        XCTAssertEqual(fileName.label, "MMQ02681.ARW")
        print(
            "Detail navigation swipe to next filename (informational, XCTest input included): \(navigationStart.duration(to: .now))"
        )
        navigationPreview.swipeRight()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        info.tap()
        XCTAssertTrue(app.staticTexts["Sample camera · 0123"].exists)
        XCTAssertTrue(app.staticTexts["24–70 mm"].exists)
        XCTAssertTrue(
            app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", ":05.42")).firstMatch
                .exists)
        element(app, "clove.detail.info.done").tap()
        element(app, "clove.detail.capsule.label").tap()
        element(app, "clove.detail.labels.green").tap()
        XCTAssertFalse(element(app, "clove.detail.labels").exists)
        let preview = navigationPreview
        let zoom = element(app, "clove.detail.zoom")
        let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.doubleTap()
        XCTAssertEqual(zoom.label, "3 / 36 · 100%")
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        XCTAssertFalse(element(app, "clove.detail.info").exists)
        XCTAssertFalse(element(app, "clove.detail.undo").exists)
        centre.tap()
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        centre.doubleTap()
        XCTAssertTrue(info.exists)
        centre.tap()
        XCTAssertFalse(capsule.exists)
        centre.tap()
        XCTAssertTrue(capsule.exists)
        element(app, "clove.detail.capsule.stars.4").tap()
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", fileName))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertTrue(String(describing: capsule.value).contains("4"))
        for (side, horizontalStart, nextPhoto) in [
            ("right", 0.8, "MMQ02681.ARW"),
            // Finishing the sample group advances to the following standalone photo.
            ("left-third", 0.2, "MMQ02680.ARW"),
        ] {
            let start = preview.coordinate(
                withNormalizedOffset: CGVector(dx: horizontalStart, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: -130))
            print("Swipe beside touch: \(side)")
            start.press(
                forDuration: 0.1, thenDragTo: end, withVelocity: .slow,
                thenHoldForDuration: 2)
            XCTAssertTrue(waitForLabel(nextPhoto, fileName))
            XCTAssertFalse(element(app, "clove.detail.swipeFeedback").exists)
        }
    }

    @MainActor
    func testContinuousMarkingSwipeClearsRejectsAndLowersStars() {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        let advance = app.switches["clove.settings.autoAdvanceEnabled"]
        for _ in 0..<5 {
            if advance.isHittable { break }
            app.swipeUp()
        }
        if advance.value as? String == "1" {
            advance.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
                .withOffset(CGVector(dx: -50, dy: 0)).tap()
        }
        XCTAssertEqual(advance.value as? String, "0")
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let stars = element(app, "clove.detail.capsule.stars.3")
        stars.tap()
        let capsule = element(app, "clove.detail.capsule")
        XCTAssertTrue((capsule.value as? String)?.contains("3 stars") == true)
        let start = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.35))
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 90)),
            withVelocity: XCUIGestureVelocity(rawValue: 1200), thenHoldForDuration: 0)
        XCTAssertEqual(capsule.value as? String, "Unmarked")
        element(app, "clove.detail.undo").tap()
        XCTAssertTrue((capsule.value as? String)?.contains("3 stars") == true)
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 210)),
            withVelocity: XCUIGestureVelocity(rawValue: 1200), thenHoldForDuration: 0)
        XCTAssertTrue((capsule.value as? String)?.contains("Rejected") == true)
        element(app, "clove.detail.undo").tap()
        XCTAssertTrue((capsule.value as? String)?.contains("3 stars") == true)
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 135)),
            withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0)
        XCTAssertTrue((capsule.value as? String)?.contains("1 star") == true)
        XCTAssertFalse(element(app, "clove.detail.swipeFeedback").exists)
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
            let reject = element(app, "clove.detail.capsule.reject")
            let fileName = element(app, "clove.detail.fileName")
            let capsule = element(app, "clove.detail.capsule")
            XCTAssertFalse(glyph.exists)
            reject.tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", fileName))
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
            XCTAssertEqual(preview.label, "MMQ02680.ARW, Rejected")
            let rejectedCorner = try rejectGlyphPixels(in: preview)
            XCTAssertNotEqual(rejectedCorner, unmarkedCorner)
            XCTAssertTrue(glyph.exists)
            let glyphFrame = glyph.frame
            capture("detail-rejected-\(theme)-chrome-shown")
            let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            centre.tap()
            XCTAssertFalse(capsule.exists)
            XCTAssertTrue(glyph.exists)
            XCTAssertEqual(glyph.frame, glyphFrame)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
            capture("detail-rejected-\(theme)-chrome-hidden")
            centre.doubleTap()
            XCTAssertEqual(element(app, "clove.detail.zoom").label, "3 / 36 · 100%")
            XCTAssertTrue(glyph.exists)
            XCTAssertEqual(glyph.frame, glyphFrame)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
            preview.swipeLeft()
            XCTAssertTrue(glyph.exists)
            XCTAssertEqual(glyph.frame, glyphFrame)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
            centre.doubleTap()
            centre.tap()
            reject.tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", fileName))
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
            XCTAssertEqual(preview.label, "MMQ02680.ARW")
            XCTAssertFalse(glyph.exists)
            XCTAssertEqual(try rejectGlyphPixels(in: preview), unmarkedCorner)
            app.terminate()
        }
    }

    /// Sample the opaque centre of the 22 pt glyph, inset 8 pt in the stage.
    @MainActor
    private func rejectGlyphPixels(in preview: XCUIElement) throws -> Data {
        let screenshot = XCUIScreen.main.screenshot().image
        let frame = preview.frame
        let region = CGRect(
            x: frame.maxX - 25, y: frame.minY + 13, width: 12, height: 12
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
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "3 / 36 · 100%")
    }

    @MainActor
    func testDisconnectedFolderBanner() {
        let disconnected = launchSample(["CLOVE_TEST_LIBRARY_LOCATION_LOSS": "drive"])
        openLibrary(disconnected)
        XCTAssertEqual(element(disconnected, "clove.grid.saveState").label, "Not connected")
        XCTAssertTrue(disconnected.staticTexts["The drive disconnected."].exists)
        XCTAssertTrue(element(disconnected, "clove.grid.saveState.failure.action").exists)
        element(disconnected, "clove.grid.group.burst-2678").tap()
        XCTAssertTrue(element(disconnected, "clove.detail").exists)
        XCTAssertTrue(element(disconnected, "clove.detail.saveStatus.failure.action").exists)
    }

    /// A stack uses detail; one undo restores every photo rejected by the finishing pill.
    @MainActor
    func testStackOpensDetailAndFinishingUndoRestoresUnmarkedTogether() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        openLibrary(app)
        let group = element(app, "clove.grid.group.burst-2678")
        let fileName = element(app, "clove.detail.fileName")
        group.tap()
        XCTAssertEqual(fileName.label, "MMQ02678.ARW")
        XCTAssertTrue(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        XCTAssertFalse(element(app, "clove.detail.rejectUnmarked").exists)
        element(app, "clove.detail.capsule.label").tap()
        element(app, "clove.detail.labels.green").tap()
        element(app, "clove.nav.back").tap()
        group.tap()
        XCTAssertEqual(fileName.label, "MMQ02679.ARW")
        let pill = element(app, "clove.detail.rejectUnmarked")
        XCTAssertEqual(pill.label, "Reject 2 unmarked")
        pill.tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        XCTAssertFalse(pill.exists)
        element(app, "clove.detail.undo").tap()
        XCTAssertEqual(fileName.label, "MMQ02679.ARW")
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
        let label = element(app, "clove.detail.capsule.label")
        label.tap()
        element(app, "clove.detail.labels.green").tap()
        XCTAssertEqual(label.label, "Label, Green")
        // A label choice keeps this title. A predicate wait can time out taking its snapshot
        // under load even when the title is already correct (#166).
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02678.ARW")
        XCTAssertFalse(element(app, "clove.detail.rejectUnmarked").exists)
    }

    @MainActor
    func testGroupZoomKeepsTheCropUntilLeavingItsMembers() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        openLibrary(app)
        element(app, "clove.grid.group.burst-2678").tap()
        let preview = element(app, "clove.detail.preview")
        let fileName = element(app, "clove.detail.fileName")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertFalse(element(app, "clove.detail.info").exists)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertEqual(fileName.label, "MMQ02679.ARW")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertFalse(element(app, "clove.detail.info").exists)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertTrue(element(app, "clove.detail.info").exists)
    }

    @MainActor
    func testMoveRejectsConfirmsAndReportsFilesLeftInPlace() {
        let app = launchSample([
            "CLOVE_TEST_LIBRARY_MOVE_FAIL_STEM_SUFFIX": "5",
            "CLOVE_TEST_LIBRARY_KEEP_TOAST": "1",
        ])
        openLibrary(app)
        element(app, "clove.grid.moveRejects").tap()
        XCTAssertEqual(element(app, "clove.moves.confirmation").label, "Move 2 rejected photos")
        element(app, "clove.moves.expand").tap()
        element(app, "clove.moves.keep.mmq02679").tap()
        element(app, "clove.moves.confirm").tap()
        let undo = element(app, "clove.moves.toast.action")
        XCTAssertTrue(undo.waitForExistence(timeout: 5))
        XCTAssertEqual(undo.label, "Undo")
        element(app, "clove.moves.toast.secondaryAction").tap()
        XCTAssertTrue(element(app, "clove.moves.details.row.mmq02685").exists)
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
        XCTAssertTrue(element(app, "clove.moves.details.sheet").exists)
    }

    @MainActor
    func testDesignGalleryShowsSharedControls() {
        let app = launchSample(["CLOVE_DESIGN_GALLERY": "1"])
        XCTAssertTrue(element(app, "clove.design.gallery").exists)
        XCTAssertTrue(element(app, "clove.mark.capsule").exists)
        XCTAssertTrue(element(app, "clove.mark.starBar").exists)
        let nord = element(app, "clove.design.gallery.theme.nord")
        nord.tap()
        XCTAssertTrue(nord.isSelected)
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
            XCTAssertTrue(pill.exists)
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
            XCTAssertTrue(element(app, "clove.detail.rejectUnmarked").exists)
            capture("detail-expanded-group-\(theme)")
            element(app, "clove.detail.rejectUnmarked").tap()
            XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
            element(app, "clove.nav.back").tap()
            element(app, "clove.grid.moveRejects").tap()
            XCTAssertTrue(element(app, "clove.moves.expand").exists)
            capture("move-confirm-\(theme)")
            element(app, "clove.moves.expand").tap()
            element(app, "clove.moves.keep.mmq02685").tap()
            XCTAssertEqual(element(app, "clove.moves.partial").label, "2 of 3 will move")
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
                element(partial, "clove.moves.details.sheet").exists)
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
            XCTAssertTrue(element(app, "clove.detail.filmstrip").exists)
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
            XCTAssertTrue(element(app, "clove.design.gallery").exists)
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
            XCTAssertTrue(element(app, "clove.grid.filter.all").exists)
            capture("grid-filter-\(theme)")
            element(app, "clove.grid.filter.all").tap()
            element(app, "clove.grid.more").tap()
            XCTAssertTrue(app.buttons["Settings"].exists)
            capture("grid-more-\(theme)")
            // The native menu overlaps the title. A tap to its left dismisses it.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.04, dy: 0.6)).tap()
            let photo = element(app, "clove.grid.photo.mmq02680")
            photo.press(forDuration: 0.6)
            XCTAssertTrue(element(app, "clove.grid.batch.done").exists)
            capture("grid-select-\(theme)")
            element(app, "clove.grid.batch.done").tap()
            photo.tap()
            XCTAssertTrue(element(app, "clove.detail.capsule").exists)
            capture("detail-\(theme)")
            element(app, "clove.detail.capsule.label").tap()
            XCTAssertTrue(element(app, "clove.detail.labels.green").exists)
            capture("detail-labels-\(theme)")
            element(app, "clove.detail.labels.green").tap()
            element(app, "clove.detail.info").tap()
            XCTAssertTrue(app.staticTexts["Sample camera · 0123"].exists)
            capture("detail-info-\(theme)")
            element(app, "clove.detail.info.done").tap()
            let preview = element(app, "clove.detail.preview")
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
            XCTAssertFalse(element(app, "clove.detail.capsule").exists)
            capture("detail-zoom-\(theme)")
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
            element(app, "clove.detail.capsule.reject").tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", element(app, "clove.detail.fileName")))
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
            XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))
            capture("detail-rejected-\(theme)")
            element(app, "clove.nav.back").tap()
            app.swipeUp()
            XCTAssertTrue(element(app, "clove.grid.photo.mmq02700").exists)
            capture("grid-no-preview-\(theme)")
            app.terminate()
        }
        for stage in ["reading", "grouping"] {
            let app = launchSample(["CLOVE_TEST_LIBRARY_OPENING": stage])
            openLibrary(app)
            capture("grid-opening-\(stage)")
            XCTAssertFalse(element(app, "clove.grid.moveRejects").exists)
            element(app, "clove.grid.photo.mmq02680").tap()
            XCTAssertTrue(element(app, "clove.detail.capsule").exists)
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
        XCTAssertTrue(app.staticTexts["Sample camera · 0123"].exists)
        capture("detail-info-compact")
        element(app, "clove.detail.info.done").tap()
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        XCTAssertTrue(
            element(app, "clove.settings.appearance.theme.light").exists)
        capture("theme-tiles")
        app.terminate()
        let opening = launchSample(["CLOVE_TEST_LIBRARY_OPENING": "empty"])
        openLibrary(opening)
        XCTAssertTrue(opening.collectionViews.firstMatch.exists)
        XCTAssertFalse(element(opening, "clove.grid.moveRejects").exists)
        capture("grid-opening-before-first-photo")
    }

    @MainActor
    func launchSample(_ environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["CLOVE_TEST_LIBRARY": "1"].merging(environment) { _, new in new }
        app.launch()
        let root =
            environment["CLOVE_DESIGN_GALLERY"] == "1" ? "clove.design.gallery" : "clove.root"
        XCTAssertTrue(element(app, root).waitForExistence(timeout: 15))
        return app
    }

    @MainActor
    func openLibrary(_ app: XCUIApplication) {
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
    func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    @MainActor
    func waitForLabel(_ label: String, _ target: XCUIElement) -> Bool {
        wait(NSPredicate(format: "label == %@", label), target)
    }

    @MainActor
    func wait(_ predicate: NSPredicate, _ target: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        // Real async work may already be finished. Read once before starting a predicate timer:
        // under load, that first accessibility snapshot can itself exceed a short deadline.
        if predicate.evaluate(with: target) { return true }
        return XCTWaiter.wait(
            for: [XCTNSPredicateExpectation(predicate: predicate, object: target)], timeout: timeout
        )
            == .completed
    }

    @MainActor
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
