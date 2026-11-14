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
        if #available(iOS 27.1, *) {
            XCTAssertTrue(move.isHittable)
        } else {
            XCTAssertEqual(move.frame.width, 40, accuracy: 1)
        }
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
        // The push that covers the grid animates; read the settled state instead of one
        // snapshot taken mid-transition (#203's observed-state pattern).
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), element(app, "clove.grid")))
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
        if #available(iOS 27.1, *) {
            XCTAssertTrue(element(app, "clove.detail.info").isHittable)
        } else {
            XCTAssertEqual(element(app, "clove.detail.info").frame.width, 40, accuracy: 1)
        }
        stars.tap()
        XCTAssertTrue(stars.isSelected)
        stars.tap()
        XCTAssertFalse(stars.isSelected)
        // The rail embeds the shared picker's unglassed column: dots are tapped directly
        // (#229), and tapping the current colour again clears it.
        green.tap()
        XCTAssertTrue(green.isSelected)
        green.tap()
        XCTAssertFalse(green.isSelected)
        green.tap()
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
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), strip))
        XCTAssertTrue(rail.isHittable)
        XCTAssertEqual(preview.frame, stageFrame)
        XCTAssertEqual(rail.frame, railFrame)
        XCTAssertFalse(element(app, "clove.detail.info").exists)
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
        centre.doubleTap()
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "3 / 36 · 100%")
        XCTAssertFalse(strip.exists)
        XCTAssertTrue(rail.isHittable)
        XCTAssertEqual(preview.frame, stageFrame)
        centre.doubleTap()
        // The fit that restores the chrome lands after the double tap returns (#203).
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
        reject.tap()
        XCTAssertEqual(reject.label, "Rejected")
        XCTAssertTrue(element(app, "clove.detail.rejectGlyph").exists)
        XCTAssertFalse(stars.isSelected)
        // Reject neutralises the rail's dots; the ladder keeps no selection.
        XCTAssertFalse(green.isSelected)
        XCTAssertLessThan(element(app, "clove.detail.rejectGlyph").frame.maxX, rail.frame.minX)
        capture("ipad-detail-rail-rejected")
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), strip))
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
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02683").tap()
        let focusToggle = element(app, "clove.detail.focusToggle")
        let overlapAF = element(app, "clove.detail.region.af.0")
        let separatedEye = element(app, "clove.detail.region.face.4-1")
        XCTAssertTrue(focusToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(focusToggle.value as? String, "On")
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
        XCTAssertTrue(separatedEye.exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.1-0").exists)
        capture("ipad-detail-focus-on")
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), focusToggle))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), overlapAF))
        XCTAssertFalse(separatedEye.exists)
        capture("ipad-detail-focus-off")
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), focusToggle))
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
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
        openSettingsCategory("clove.settings.category.culling", in: app)
        let destination = element(app, "clove.settings.autoAdvanceDestination")
        for _ in 0..<5 {
            if destination.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(destination.waitForExistence(timeout: 5))
        destination.tap()
        let stay = element(app, "clove.settings.autoAdvance.stay")
        XCTAssertTrue(stay.waitForExistence(timeout: 5))
        stay.tap()
        XCTAssertTrue(stay.isSelected)
    }

    @MainActor
    private func chooseRailTheme(_ theme: String, _ app: XCUIApplication) {
        openSettingsCategory("clove.settings.category.appearance", in: app)
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
        XCTAssertFalse(element(disconnected, "clove.detail.rail.label").isEnabled)
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
        let capsule = element(app, "clove.detail.capsule")
        XCTAssertTrue(capsule.exists)
        XCTAssertEqual(capsule.frame.width, 168, accuracy: 1)
        XCTAssertEqual(capsule.frame.height, 48, accuracy: 1)
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
        let toast = element(app, "clove.save.toast")
        let filmstrip = element(app, "clove.detail.filmstrip")
        let capsule = element(app, "clove.detail.capsule")
        XCTAssertTrue(toast.exists)
        XCTAssertLessThan(toast.frame.midY, filmstrip.frame.minY)
        XCTAssertLessThan(toast.frame.maxY, capsule.frame.minY)
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
        rate(3, in: app)
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
        XCTAssertTrue(element(app, "clove.grid.batch.rating").isEnabled)
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
        let previewFrame = navigationPreview.frame
        let fitMiddle = navigationPreview.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        fitMiddle.press(
            forDuration: 0.1, thenDragTo: fitMiddle.withOffset(CGVector(dx: -50, dy: 0)),
            withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(navigationPreview.frame, previewFrame)
        let navigationStart = ContinuousClock.now
        navigationPreview.swipeLeft()
        XCTAssertEqual(fileName.label, "MMQ02681.ARW")
        XCTAssertEqual(navigationPreview.frame, previewFrame)
        print(
            "Detail navigation swipe to next filename (informational, XCTest input included): \(navigationStart.duration(to: .now))"
        )
        navigationPreview.swipeRight()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(navigationPreview.frame, previewFrame)
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
        // A horizontal drag while zoomed pans the scroll view instead of stepping photos.
        preview.swipeLeft()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        centre.doubleTap()
        // The fit animation restores the chrome after the double tap returns, so this reads
        // the observed state instead of asserting one immediate snapshot.
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), info))
        // Single taps anywhere (centre or outer edges) toggle chrome after waiting for double-tap
        // and never navigate.
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), capsule))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), capsule))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        rate(4, in: app)
        // A mark waits out the advance pause before the file name changes. On a loaded runner
        // one accessibility query can consume most of a short window while the app is already
        // correct (#203), so this boundary keeps the 10-second budget the browsing flow uses.
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", fileName, timeout: 10))
        preview.swipeRight()
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
            // The swipe's mark advances after the pause; the marking gesture leaves the runner
            // busiest, so this wait keeps the same 10-second advance budget as above (#203).
            XCTAssertTrue(waitForLabel(nextPhoto, fileName, timeout: 10))
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
        turnOffAutoAdvance(app)
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        rate(3, in: app)
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
            preview.swipeRight()
            XCTAssertEqual(preview.label, "MMQ02680.ARW, Rejected")
            let rejectedCorner = try rejectGlyphPixels(in: preview)
            XCTAssertNotEqual(rejectedCorner, unmarkedCorner)
            XCTAssertTrue(glyph.exists)
            let glyphFrame = glyph.frame
            capture("detail-rejected-\(theme)-chrome-shown")
            let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
            centre.tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), capsule))
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
            XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
            reject.tap()
            XCTAssertTrue(waitForLabel("MMQ02681.ARW", fileName))
            preview.swipeRight()
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
        openSettingsCategory("clove.settings.category.photoDisplay", in: app)
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
        defer { app.terminate() }
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
        defer { app.terminate() }
        openLibrary(app)
        element(app, "clove.grid.group.burst-2678").tap()
        let preview = element(app, "clove.detail.preview")
        let fileName = element(app, "clove.detail.fileName")
        let info = element(app, "clove.detail.info")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), info))
        // While zoomed, single taps near the edges and horizontal swipes do not navigate (#252).
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertEqual(fileName.label, "MMQ02678.ARW")
        preview.swipeLeft()
        XCTAssertEqual(fileName.label, "MMQ02678.ARW")
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForLabel("MMQ02679.ARW", fileName))
        XCTAssertTrue(
            wait(NSPredicate(format: "value BEGINSWITH %@", "Loaded, centred at"), preview))
        XCTAssertFalse(info.exists)
        app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), info))
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
        XCTAssertTrue(element(app, "clove.mark.toolbar").exists)
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
            rate(3, in: app)
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

    /// Opt-in visual evidence for the neutral group badge and the expanded filmstrip surface.
    ///
    /// The sample's first group is widened to two and to three digits for the run, so the
    /// captures show both counts on bright and dimmed photos, and the current group's surface in
    /// the filmstrip. Nothing is asserted about colour: the images are for a person to compare.
    /// The filter lives in the toolbar on iPhone and in the sidebar on iPad, so both are used.
    @MainActor
    func testCaptureGroupBadgeReferencesWhenRequested() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["CLOVE_CAPTURE_GROUP_BADGES"] == "1")
        for count in ["12", "123"] {
            for theme in ["light", "dark", "nord"] {
                let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_COUNT": count])
                openLibrary(app)
                applyComparisonTheme(theme, app)
                capture("group-badge-\(count)-grid-\(theme)")
                let toolbarFilter = element(app, "clove.grid.filter")
                if toolbarFilter.exists {
                    toolbarFilter.tap()
                    element(app, "clove.grid.filter.rejected").tap()
                } else {
                    element(app, "clove.sidebar.rejected").tap()
                }
                capture("group-badge-\(count)-grid-rejected-\(theme)")
                if toolbarFilter.exists {
                    toolbarFilter.tap()
                    element(app, "clove.grid.filter.all").tap()
                } else {
                    element(app, "clove.sidebar.all").tap()
                }
                element(app, "clove.grid.photo.mmq02682").tap()
                XCTAssertTrue(element(app, "clove.detail.filmstrip").exists)
                capture("group-badge-\(count)-filmstrip-\(theme)")
                element(app, "clove.detail.filmstrip.group.burst-2678").tap()
                XCTAssertTrue(waitForLabel("MMQ02678.ARW", element(app, "clove.detail.fileName")))
                XCTAssertTrue(element(app, "clove.detail.filmstrip.expandedGroup").exists)
                capture("group-badge-\(count)-filmstrip-expanded-\(theme)")
                // Leave detail before terminating, so the next launch restores the grid.
                element(app, "clove.nav.back").tap()
                XCTAssertTrue(element(app, "clove.grid.more").waitForExistence(timeout: 5))
                app.terminate()
            }
        }
    }

    @MainActor
    private func applyComparisonTheme(_ theme: String, _ app: XCUIApplication) {
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        chooseTheme(theme, app)
        element(app, "clove.nav.back").tap()
    }

    /// Opt-in visual evidence for the detail filmstrip's settled geometry: the strip dragged to
    /// the folder's last photo, so a person can compare where the content rests at its end
    /// before and after the single-reservation fix (#237). Runs on whatever device the runner
    /// picks; nothing is asserted, the captures are for comparison.
    @MainActor
    func testCaptureFilmstripEndReferencesWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_FILMSTRIP"] == "1")
        for theme in ["light", "dark"] {
            let app = launchSample()
            openLibrary(app)
            applyComparisonTheme(theme, app)
            element(app, "clove.grid.photo.mmq02680").tap()
            XCTAssertTrue(element(app, "clove.detail.filmstrip").waitForExistence(timeout: 5))
            capture("filmstrip-start-\(theme)")
            let strip = element(app, "clove.detail.filmstrip")
            let last = element(app, "clove.detail.filmstrip.mmq02713")
            for _ in 0..<14 where !restsAtTrailingEdge(last, of: strip) {
                dragStripForward(strip)
            }
            capture("filmstrip-end-\(theme)")
            element(app, "clove.nav.back").tap()
            app.terminate()
        }
    }

    /// Opt-in visual evidence for the shared marking family: every rating value, clear versus
    /// Reject, labeled-unrated, the ladder and label picker, and both Entry states, in Light,
    /// Dark and one alternate theme (#227).
    @MainActor
    func testCaptureMarkingControlsWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_MARKING"] == "1")
        for theme in ["light", "dark", "nord"] {
            let app = launchSample()
            defer { app.terminate() }
            openLibrary(app)
            applyComparisonTheme(theme, app)
            // Keep each rated photo on screen, so the captures show the value it carries.
            element(app, "clove.grid.more").tap()
            app.buttons["Settings"].tap()
            turnOffAutoAdvance(app)
            element(app, "clove.nav.back").tap()
            element(app, "clove.grid.photo.mmq02680").tap()
            let capsule = element(app, "clove.detail.capsule")
            capture("marking-unrated-\(theme)")
            for value in 1...5 {
                rate(value, in: app)
                XCTAssertTrue(
                    wait(NSPredicate(format: "value CONTAINS %@", "\(value) star"), capsule))
                capture("marking-\(value)star-\(theme)")
            }
            // Clear via tap-current, then label an unrated photo: label and rating stay
            // independent.
            rate(5, in: app)
            XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Unmarked"), capsule))
            capture("marking-cleared-\(theme)")
            element(app, "clove.detail.capsule.label").tap()
            XCTAssertTrue(element(app, "clove.detail.labels.blue").waitForExistence(timeout: 5))
            capture("marking-label-picker-\(theme)")
            element(app, "clove.detail.labels.blue").tap()
            XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Blue"), capsule))
            capture("marking-labeled-unrated-\(theme)")
            // Reject keeps the label in the file but reads Rejected; the corner glyph shows.
            element(app, "clove.detail.capsule.reject").tap()
            XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Rejected"), capsule))
            XCTAssertTrue(element(app, "clove.detail.rejectGlyph").exists)
            capture("marking-rejected-\(theme)")
            // The ladder itself, opened from the rating action.
            element(app, "clove.detail.capsule.rating").tap()
            XCTAssertTrue(
                element(app, "clove.detail.capsule.stars").waitForExistence(timeout: 5))
            capture("marking-ladder-\(theme)")
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)).tap()
            // Mixed batch state in select mode.
            element(app, "clove.nav.back").tap()
            let rated = element(app, "clove.grid.photo.mmq02678")
            rated.press(forDuration: 0.6)
            element(app, "clove.grid.photo.mmq02680").tap()
            capture("marking-mixed-batch-\(theme)")
            element(app, "clove.grid.batch.rating").tap()
            XCTAssertTrue(
                element(app, "clove.grid.batch.stars.3").waitForExistence(timeout: 5))
            capture("marking-batch-ladder-\(theme)")
            element(app, "clove.grid.batch.done").tap()
            // Entry's two states: resume with a legible Reconnect is covered by the sample's
            // reconnect variant; the plain resume and Open folder button show here.
            element(app, "clove.nav.back").tap()
            capture("marking-entry-resume-\(theme)")
        }
        // The disconnected-row Reconnect chip stays legible on its neutral capsule; the
        // sample's third recent is a missing drive. The first-launch state has no sample
        // lever, so its Open folder button is covered by the design gallery and flows.
        let entry = launchSample()
        XCTAssertTrue(
            element(entry, "clove.entry.reconnect").waitForExistence(timeout: 5))
        capture("marking-entry-reconnect")
        entry.terminate()
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
            preview.swipeRight()
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
        openSettingsCategory("clove.settings.category.appearance", in: app)
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

    /// Explicit Settings capture run (`TEST_RUNNER_CLOVE_CAPTURE_SETTINGS=1`). Skipped in regular
    /// flow runs; captures every reorganized category, subpage, and reset confirmation in Light
    /// and Dark across both compact (iPhone) and wide split (iPad) layouts.
    @MainActor
    func testCaptureSettingsReferencesWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_SETTINGS"] == "1")
        let isWide = XCUIScreen.main.screenshot().image.size.width > 700
        let prefix = isWide ? "settings-ipad" : "settings-iphone"

        for theme in ["light", "dark"] {
            let app = launchSample()
            openSettings(in: app)
            chooseTheme(theme, app)

            if isWide {
                capture("\(prefix)-appearance-\(theme)")

                openSettingsCategory("clove.settings.category.culling", in: app)
                capture("\(prefix)-culling-\(theme)")

                scrollToSettingsControl("clove.settings.ratingScale", in: app).tap()
                XCTAssertTrue(
                    element(app, "clove.settings.rating.1").waitForExistence(timeout: 5))
                capture("\(prefix)-rating-scale-\(theme)")
                if app.navigationBars.buttons["Culling & marking"].exists {
                    app.navigationBars.buttons["Culling & marking"].tap()
                } else {
                    app.navigationBars.buttons["Settings"].tap()
                    openSettingsCategory("clove.settings.category.culling", in: app)
                }

                scrollToSettingsControl("clove.settings.autoAdvanceDestination", in: app).tap()
                XCTAssertTrue(
                    element(app, "clove.settings.autoAdvance.stay").waitForExistence(timeout: 5))
                capture("\(prefix)-after-marking-\(theme)")
                if app.navigationBars.buttons["Culling & marking"].exists {
                    app.navigationBars.buttons["Culling & marking"].tap()
                } else {
                    app.navigationBars.buttons["Settings"].tap()
                }

                openSettingsCategory("clove.settings.category.browsing", in: app)
                capture("\(prefix)-browsing-\(theme)")

                openSettingsCategory("clove.settings.category.photoDisplay", in: app)
                capture("\(prefix)-photo-display-\(theme)")

                openSettingsCategory("clove.settings.category.moveRejects", in: app)
                capture("\(prefix)-move-rejects-\(theme)")
            } else {
                capture("\(prefix)-appearance-\(theme)")

                app.navigationBars.buttons["Settings"].tap()
                XCTAssertTrue(
                    element(app, "clove.settings.category.appearance").waitForExistence(timeout: 5))
                capture("\(prefix)-home-\(theme)")

                openSettingsCategory("clove.settings.category.culling", in: app)
                capture("\(prefix)-culling-\(theme)")

                scrollToSettingsControl("clove.settings.ratingScale", in: app).tap()
                XCTAssertTrue(
                    element(app, "clove.settings.rating.1").waitForExistence(timeout: 5))
                capture("\(prefix)-rating-scale-\(theme)")
                app.navigationBars.buttons["Culling & marking"].tap()

                scrollToSettingsControl("clove.settings.autoAdvanceDestination", in: app).tap()
                XCTAssertTrue(
                    element(app, "clove.settings.autoAdvance.stay").waitForExistence(timeout: 5))
                capture("\(prefix)-after-marking-\(theme)")
                app.navigationBars.buttons["Culling & marking"].tap()
                app.navigationBars.buttons["Settings"].tap()

                openSettingsCategory("clove.settings.category.browsing", in: app)
                capture("\(prefix)-browsing-\(theme)")
                app.navigationBars.buttons["Settings"].tap()

                openSettingsCategory("clove.settings.category.photoDisplay", in: app)
                capture("\(prefix)-photo-display-\(theme)")
                app.navigationBars.buttons["Settings"].tap()

                openSettingsCategory("clove.settings.category.moveRejects", in: app)
                capture("\(prefix)-move-rejects-\(theme)")
                app.navigationBars.buttons["Settings"].tap()
            }

            let reset = element(app, "clove.settings.reset")
            for _ in 0..<4 where !reset.isHittable { app.swipeUp() }
            reset.tap()
            let alert = app.alerts["Reset settings to defaults?"]
            XCTAssertTrue(alert.waitForExistence(timeout: 5))
            capture("\(prefix)-reset-alert-\(theme)")
            alert.buttons["Reset"].tap()
            app.terminate()
        }
    }

    /// Runs on the Duo's actual inner display. The Open pose must be selected in
    /// Device Hub on an unlocked GUI session; no headless lever exists for it.
    @MainActor
    func testDuoGridFocusDockMarkAndPhotoOnly() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        let app = launchSample()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        openLibrary(app)
        try XCTSkipUnless(
            app.windows.firstMatch.horizontalSizeClass == .regular,
            "the Duo is not in the Open pose; select Open in Device Hub to test the inner display")
        prepareDuo(app)
        exerciseDuo(app)
    }

    @MainActor
    private func prepareDuo(_ app: XCUIApplication) {
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        turnOffAutoAdvance(app)
        element(app, "clove.nav.back").tap()
    }

    @MainActor
    private func exerciseDuo(_ app: XCUIApplication) {
        XCTAssertFalse(element(app, "clove.sidebar").exists)
        XCTAssertFalse(element(app, "clove.duo.rating").exists)
        XCTAssertFalse(element(app, "clove.duo.capsule").exists)
        capture("duo-grid")
        element(app, "clove.grid.photo.mmq02680").tap()
        let focus = element(app, "clove.duo.focus")
        XCTAssertTrue(focus.waitForExistence(timeout: 5))
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertFalse(element(app, "clove.detail.rail").exists)
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        XCTAssertFalse(element(app, "clove.detail.filmstrip").exists)
        let grid = app.collectionViews.firstMatch
        XCTAssertEqual(
            grid.frame.width / (grid.frame.width + focus.frame.width), 0.3, accuracy: 0.02)
        // #200: the marking capsule reserves its own row beneath the fitted photo, and
        // the side toolbar carries no duplicate marking items.
        let capsule = element(app, "clove.duo.capsule")
        XCTAssertTrue(capsule.exists)
        XCTAssertEqual(capsule.frame.width, 168, accuracy: 1)
        XCTAssertEqual(capsule.frame.height, 48, accuracy: 1)
        XCTAssertGreaterThanOrEqual(capsule.frame.minY, preview.frame.maxY)
        XCTAssertEqual(capsule.frame.maxX, focus.frame.maxX - 16, accuracy: 1)
        XCTAssertFalse(element(app, "clove.duo.rating").exists)
        XCTAssertFalse(element(app, "clove.duo.reject").exists)
        XCTAssertFalse(element(app, "clove.duo.label").exists)
        capture("duo-focus")
        rate(3, toolbar: "clove.duo.capsule", in: app)
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "3 stars"), capsule))
        rate(5, toolbar: "clove.duo.capsule", in: app)
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "5 stars"), capsule))
        element(app, "clove.duo.undo").tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "3 stars"), capsule))
        // Tapping the current rating clears it; Undo restores it.
        rate(3, toolbar: "clove.duo.capsule", in: app)
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Unmarked"), capsule))
        element(app, "clove.duo.undo").tap()
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "3 stars"), capsule))
        capture("duo-capsule")
        element(app, "clove.duo.capsule.label").tap()
        XCTAssertTrue(element(app, "clove.duo.labels.green").waitForExistence(timeout: 5))
        capture("duo-labels")
        element(app, "clove.duo.labels.green").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "label CONTAINS[c] %@", "green"),
                element(app, "clove.duo.capsule.label")))
        let divider = element(app, "clove.duo.divider")
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.1,
            thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)))
        let filmstrip = element(app, "clove.detail.filmstrip")
        XCTAssertTrue(filmstrip.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.duo.focus").exists)
        XCTAssertTrue(element(app, "clove.detail.fileName").exists)
        // In photo only, the capsule stays beneath the photo and beside the narrowed filmstrip.
        XCTAssertGreaterThanOrEqual(capsule.frame.minY, preview.frame.maxY)
        XCTAssertGreaterThan(capsule.frame.midX, element(app, "clove.duo.photoOnly").frame.midX)
        // View frames alone cannot see the interior dead space a content-side reservation leaves
        // (#237), so the content check below inspects where the strip's content actually rests.
        XCTAssertLessThanOrEqual(filmstrip.frame.maxX, capsule.frame.minX + 1)
        capture("duo-photo-only")
        // The strip's content fills its viewport up to the toolbar: dragged to the folder's last
        // photo, its last thumbnail rests beside the toolbar rather than behind a second,
        // content-padded reservation. The drags advance one viewport at a time, so the resting
        // end is the content's real end, not a jump's estimate (#237).
        let fileName = element(app, "clove.detail.fileName")
        let last = element(app, "clove.detail.filmstrip.mmq02713")
        for _ in 0..<14 where !restsAtTrailingEdge(last, of: filmstrip) {
            dragStripForward(filmstrip)
        }
        XCTAssertTrue(
            wait(NSPredicate { _, _ in self.restsAtTrailingEdge(last, of: filmstrip) }, last),
            "the last thumbnail stops short of the toolbar: the marking area is reserved twice")
        capture("duo-photo-only-strip-end")
        // Opening it moves the current photo far in one step; the strip must still land on it.
        last.tap()
        XCTAssertTrue(waitForLabel("MMQ02713.ARW", fileName))
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), last),
            "the strip went blank after the far jump")
        // Entering the group from its stack and leaving it again cover the other directions of
        // the same identity change beside the toolbar (#237).
        let stack = swipeStripUntilHittable(
            "clove.detail.filmstrip.group.burst-2678", in: app, forward: false)
        stack.tap()
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", fileName))
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5))
        let exit = swipeStripUntilHittable(
            "clove.detail.filmstrip.mmq02680", in: app, forward: true)
        exit.tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.filmstrip.expandedGroup")))
        let current = element(app, "clove.detail.filmstrip.mmq02680")
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), current),
            "the strip went blank after leaving the group")
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02680").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.duo.capsule").exists)
    }

    /// #225: a group opened in expanded Duo expands in place in the folder grid, so the folder's
    /// own photos stay reachable around it. Folding the group keeps the photo, its marks and the
    /// route; the stack reopens it, and Back returns to the full folder grid.
    @MainActor
    func testDuoExpandedGroupMembersBrowseBesideThePhoto() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        openLibrary(app)
        try XCTSkipUnless(
            app.windows.firstMatch.horizontalSizeClass == .regular,
            "Select Open in Device Hub to test the Duo inner display")
        prepareDuo(app)
        // The second burst sits between folder photos, so the split pane shows both around it.
        element(app, "clove.grid.group.burst-2696").tap()
        XCTAssertTrue(element(app, "clove.duo.focus").waitForExistence(timeout: 5))
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", preview))
        // The folder's own photos stay in the pane around the expanded group.
        let before = element(app, "clove.grid.photo.mmq02695")
        let after = element(app, "clove.grid.photo.mmq02699")
        XCTAssertTrue(before.exists, "The photo before the group left the folder grid")
        XCTAssertTrue(after.exists, "The photo after the group left the folder grid")
        XCTAssertFalse(element(app, "clove.grid.group.burst-2696").exists)
        let count = element(app, "clove.grid.group.count.burst-2696")
        XCTAssertTrue(count.exists, "The expanded group has no header")
        XCTAssertEqual(count.label, "3 photos")
        let first = element(app, "clove.grid.photo.mmq02696")
        let third = element(app, "clove.grid.photo.mmq02698")
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(third.isSelected)
        // Folding changes the thumbnails only: the photo, its name and the route stay, and the
        // group folds at its own position without jumping (#241).
        let beforeExpanded = before.frame
        let headerExpanded = count.frame
        element(app, "clove.grid.group.fold").tap()
        XCTAssertFalse(element(app, "clove.grid.group.count.burst-2696").exists)
        let stack = element(app, "clove.grid.group.burst-2696")
        XCTAssertTrue(stack.waitForExistence(timeout: 5), "Folding did not leave the group's stack")
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", preview))
        XCTAssertTrue(before.exists && after.exists)
        XCTAssertEqual(before.frame.minY, beforeExpanded.minY, accuracy: 2)
        XCTAssertEqual(stack.frame.minY, headerExpanded.minY, accuracy: 2)
        capture("duo-group-inline-grid-folded")
        // The stack reopens the group in place, without leaving the photo or moving neighbors.
        let beforeCollapsed = before.frame
        let stackCollapsed = stack.frame
        stack.tap()
        XCTAssertTrue(
            element(app, "clove.grid.group.count.burst-2696").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", preview))
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02696").isSelected)
        XCTAssertEqual(before.frame.minY, beforeCollapsed.minY, accuracy: 2)
        XCTAssertEqual(count.frame.minY, stackCollapsed.minY, accuracy: 2)
        capture("duo-group-inline-grid")
        // A member tap moves the preview, the filename, the highlight and the marks, without jumping.
        let firstBeforeMemberTap = first.frame
        third.tap()
        XCTAssertTrue(waitForLabel("MMQ02698.ARW", preview))
        XCTAssertTrue(third.isSelected)
        XCTAssertFalse(first.isSelected)
        XCTAssertTrue(before.exists && after.exists)
        XCTAssertEqual(before.frame.minY, beforeCollapsed.minY, accuracy: 2)
        XCTAssertEqual(first.frame.minY, firstBeforeMemberTap.minY, accuracy: 2)
        let capsule = element(app, "clove.duo.capsule")
        rate(4, toolbar: "clove.duo.capsule", in: app)
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "4 stars"), capsule))
        XCTAssertTrue(third.label.contains("4 stars"))
        // Photo only keeps the same photo, the folder-order counter and the folder-order strip.
        let grid = app.collectionViews.firstMatch
        let divider = element(app, "clove.duo.divider")
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.1,
            thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)))
        XCTAssertTrue(element(app, "clove.detail.filmstrip").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02698.ARW")
        XCTAssertTrue(
            element(app, "clove.detail.zoom").label.hasPrefix("21 / 36"),
            "The counter left the folder order: \(element(app, "clove.detail.zoom").label)")
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").exists,
            "The photo-only strip did not expand the current group")
        let stripNeighbor = element(app, "clove.detail.filmstrip.mmq02695")
        XCTAssertTrue(stripNeighbor.exists)
        XCTAssertTrue(element(app, "clove.detail.filmstrip.mmq02699").exists)
        capture("duo-group-photo-only")
        // The strip folds the group to its stack in place without closing the photo or jumping.
        let stripNeighborBeforeFold = stripNeighbor.isHittable ? stripNeighbor.frame : nil
        element(app, "clove.detail.filmstrip.group.fold").tap()
        XCTAssertFalse(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        let stripStack = element(app, "clove.detail.filmstrip.group.burst-2696")
        XCTAssertTrue(stripStack.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02698.ARW")
        if let stripNeighborBeforeFold, stripNeighbor.isHittable {
            XCTAssertEqual(stripNeighbor.frame.minX, stripNeighborBeforeFold.minX, accuracy: 2)
        }
        capture("duo-group-photo-only-folded")
        let stripStackBeforeUnfold = stripStack.frame
        let stripNeighborBeforeUnfold = stripNeighbor.isHittable ? stripNeighbor.frame : nil
        stripStack.tap()
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02698.ARW")
        XCTAssertEqual(
            element(app, "clove.detail.filmstrip.mmq02696").frame.minX,
            stripStackBeforeUnfold.minX + 3, accuracy: 4)
        if let stripNeighborBeforeUnfold, stripNeighbor.isHittable {
            XCTAssertEqual(stripNeighbor.frame.minX, stripNeighborBeforeUnfold.minX, accuracy: 2)
        }
        // Back returns to the full folder grid with its filter and browsing position.
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid.more").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.grid.title").label, "Coastal light")
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02698").exists)
        XCTAssertGreaterThanOrEqual(grid.frame.width, app.frame.width * 0.95)
        capture("duo-group-back-to-grid")
    }

    /// Runs on the Duo's cover display. A Duo simulator boots in the Closed pose
    /// headlessly, so this flow runs with no Device Hub interaction.
    @MainActor
    func testDuoCoverToolbarMarkAndPickers() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)
        try XCTSkipUnless(
            app.windows.firstMatch.horizontalSizeClass == .compact,
            "the Duo is not in the Closed pose; select Closed in Device Hub to test the cover")
        prepareDuo(app)
        XCTAssertFalse(element(app, "clove.duo.dock").exists)
        XCTAssertFalse(element(app, "clove.sidebar").exists)
        capture("duo-cover")
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertTrue(element(app, "clove.detail.fileName").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.filmstrip").exists)
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        XCTAssertFalse(element(app, "clove.detail.rail").exists)
        let rating = element(app, "clove.duo.rating")
        rating.tap()
        let stars = element(app, "clove.duo.stars")
        XCTAssertTrue(stars.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(stars.frame.height, stars.frame.width)
        XCTAssertTrue(element(app, "clove.duo.stars.clear").exists)
        element(app, "clove.duo.stars.3").tap()
        XCTAssertTrue(wait(NSPredicate(format: "label CONTAINS %@", "3 stars"), rating))
        let start = rating.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(forDuration: 0.1, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -60)))
        XCTAssertTrue(wait(NSPredicate(format: "label CONTAINS %@", "5 stars"), rating))
        element(app, "clove.duo.undo").tap()
        XCTAssertTrue(wait(NSPredicate(format: "label CONTAINS %@", "3 stars"), rating))
        rating.tap()
        XCTAssertTrue(stars.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(stars.frame.midX, app.frame.midX)
        capture("duo-cover-stars")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: 0.3)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), stars))
        element(app, "clove.duo.label").tap()
        let labels = element(app, "clove.duo.labels")
        XCTAssertTrue(element(app, "clove.duo.labels.green").waitForExistence(timeout: 5))
        XCTAssertGreaterThan(labels.frame.height, labels.frame.width)
        capture("duo-cover-labels")
        element(app, "clove.duo.labels.green").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "label CONTAINS[c] %@", "green"),
                element(app, "clove.duo.label")))
        // Explicit Clear in RatingPicker clears stars while preserving the green label.
        rating.tap()
        XCTAssertTrue(stars.waitForExistence(timeout: 5))
        element(app, "clove.duo.stars.clear").tap()
        XCTAssertTrue(wait(NSPredicate(format: "label CONTAINS %@", "0 stars"), rating))
        XCTAssertTrue(
            element(app, "clove.duo.label").label.localizedCaseInsensitiveContains("green"))
        // Undo is single-step: it restores 3 stars while keeping the green label.
        element(app, "clove.duo.undo").tap()
        XCTAssertTrue(wait(NSPredicate(format: "label CONTAINS %@", "3 stars"), rating))
        XCTAssertTrue(
            element(app, "clove.duo.label").label.localizedCaseInsensitiveContains("green"))
        // Clearing the label via None keeps 3 stars, and Undo restores the green label.
        element(app, "clove.duo.label").tap()
        XCTAssertTrue(element(app, "clove.duo.labels.none").waitForExistence(timeout: 5))
        element(app, "clove.duo.labels.none").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "NOT (label CONTAINS[c] %@)", "green"),
                element(app, "clove.duo.label")))
        XCTAssertTrue(rating.label.contains("3 stars"))
        element(app, "clove.duo.undo").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "label CONTAINS[c] %@", "green"),
                element(app, "clove.duo.label")))
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02680").waitForExistence(timeout: 5))
        element(app, "clove.grid.photo.mmq02683").tap()
        let focusToggle = element(app, "clove.detail.focusToggle")
        let overlapAF = element(app, "clove.detail.region.af.0")
        let separatedEye = element(app, "clove.detail.region.face.4-1")
        XCTAssertTrue(focusToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(focusToggle.value as? String, "On")
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
        XCTAssertTrue(separatedEye.exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.1-0").exists)
        capture("duo-cover-focus-on")
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), focusToggle))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), overlapAF))
        XCTAssertFalse(separatedEye.exists)
        capture("duo-cover-focus-off")
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), focusToggle))
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
    }

    /// Runs on the Duo's cover display: the strip's content fills its viewport after leaving a
    /// group, and the last photo lands at the strip's trailing edge, not behind a padded gap.
    /// The strip is the same layout code on the cover and the expanded inner display; the
    /// expanded photo-only geometry beside the toolbar has no headless runner and is re-checked
    /// by the owner on TestFlight (#237).
    @MainActor
    func testDuoCoverFilmstripScrollsToTheCurrentPhotoAndFillsItsViewport() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        openLibrary(app)
        try XCTSkipUnless(
            app.windows.firstMatch.horizontalSizeClass == .compact,
            "the Duo is not in the Closed pose; select Closed in Device Hub to test the cover")
        prepareDuo(app)
        let fileName = element(app, "clove.detail.fileName")
        let strip = element(app, "clove.detail.filmstrip")

        // Leaving a group swaps the strip's expanded member row for the group's stack in the
        // same change that moves the current photo, so this is the blank-strip transition.
        element(app, "clove.grid.group.burst-2678").tap()
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", fileName))
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        element(app, "clove.detail.filmstrip.mmq02680").tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.filmstrip.expandedGroup")))
        XCTAssertTrue(element(app, "clove.detail.filmstrip.group.burst-2678").exists)
        // The strip shows its content around the current photo, not blank.
        let current = element(app, "clove.detail.filmstrip.mmq02680")
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), current),
            "the strip went blank after leaving the group")
        capture("duo-cover-strip-after-group-exit")

        // The strip's content fills its viewport: dragged to the folder's last photo, the last
        // thumbnail rests at the strip's trailing edge instead of behind a reserved gap. The
        // drags advance one viewport at a time, so the lazy cells materialize as the offset
        // moves and the resting end is the content's real end, not a jump's estimate (#237).
        let last = element(app, "clove.detail.filmstrip.mmq02713")
        for _ in 0..<14 where !restsAtTrailingEdge(last, of: strip) {
            dragStripForward(strip)
        }
        XCTAssertTrue(
            wait(NSPredicate { _, _ in self.restsAtTrailingEdge(last, of: strip) }, last),
            "the last thumbnail stops short of the strip's edge: its trailing area is reserved twice"
        )
        capture("duo-cover-strip-last-photo")
        // Opening it moves the current photo far in one step; the strip must still land on it.
        last.tap()
        XCTAssertTrue(waitForLabel("MMQ02713.ARW", fileName))
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), last),
            "the strip went blank after the far jump")

        // Entering a group from its stack, a within-group move, and leaving it again cover the
        // other directions of the same identity change; visible items stay anchored in place and
        // the strip still lands on off-screen destinations (#237, #241).
        let stack = swipeStripUntilHittable(
            "clove.detail.filmstrip.group.burst-2696", in: app, forward: false)
        let neighbor = element(app, "clove.detail.filmstrip.mmq02695")
        let neighborBeforeExpand = neighbor.isHittable ? neighbor.frame : nil
        let stackBeforeExpand = stack.frame
        stack.tap()
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", fileName))
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5),
            "the strip stayed blank after entering the group")
        XCTAssertEqual(
            element(app, "clove.detail.filmstrip.mmq02696").frame.minX,
            stackBeforeExpand.minX + 3, accuracy: 4)
        if let neighborBeforeExpand, neighbor.isHittable {
            XCTAssertEqual(neighbor.frame.minX, neighborBeforeExpand.minX, accuracy: 2)
        }
        let member = swipeStripUntilHittable(
            "clove.detail.filmstrip.mmq02698", in: app, forward: true)
        member.tap()
        XCTAssertTrue(waitForLabel("MMQ02698.ARW", fileName))
        let preview = element(app, "clove.detail.preview")
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02699.ARW", fileName))
        let afterGroup = element(app, "clove.detail.filmstrip.mmq02699")
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), afterGroup),
            "the strip went blank after leaving the group by navigation")
        capture("duo-cover-strip-after-navigation-exit")
    }

    /// Runs on the Duo's cover display headlessly: verifies region-centred 100% zoom across
    /// double-taps and region taps when hiding the Duo filmstrip resizes the preview container
    /// (#272). The expanded Focus split (`clove.duo.focus`) cannot enter Open pose headlessly and
    /// is verified on TestFlight.
    @MainActor
    func testDuoCoverFocusRegionsCentreNativeZoom() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] == "iPhone19,4")
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
        let app = launchSample()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        openLibrary(app)
        try XCTSkipUnless(
            app.windows.firstMatch.horizontalSizeClass == .compact,
            "the Duo is not in the Closed pose; select Closed in Device Hub to test the cover")
        prepareDuo(app)

        element(app, "clove.grid.photo.mmq02678").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let toggle = element(app, "clove.detail.focusToggle")
        let autofocus = element(app, "clove.detail.region.af.0")
        let eye = element(app, "clove.detail.region.face.1-0")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "On")
        XCTAssertTrue(autofocus.waitForExistence(timeout: 5))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))

        let zoom = element(app, "clove.detail.zoom")
        autofocus.tap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(NSPredicate(format: "value CONTAINS %@", "centred at 30%, 35%"), preview),
            "The region tap did not keep 100% centred on the AF rectangle after Duo chrome hid")
        XCTAssertTrue(autofocus.exists)
        XCTAssertFalse(eye.exists)

        preview.doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "NOT (label ENDSWITH %@)", "100%"), zoom))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))

        // Double-tapping the photo body away from the AF rectangle (and near the edges) must still
        // centre 100% on AF after the Duo filmstrip leaves the VStack and resizes the preview.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(NSPredicate(format: "value CONTAINS %@", "centred at 30%, 35%"), preview),
            "Double-tap in Duo should keep zoom centred on the AF region after layout settles")

        preview.doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "NOT (label ENDSWITH %@)", "100%"), zoom))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))

        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(NSPredicate(format: "value CONTAINS %@", "centred at 30%, 35%"), preview),
            "Edge double-tap in Duo should zoom on the preferred AF region rather than navigate")

        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "NOT (label ENDSWITH %@)", "100%"), zoom))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02678.ARW")
    }

    @MainActor
    func testFilmstripAnchorsVisibleGroupAndCentersOffscreenNavigation() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        defer { app.terminate() }
        openLibrary(app)

        element(app, "clove.grid.photo.mmq02695").tap()
        let fileName = element(app, "clove.detail.fileName")
        XCTAssertTrue(waitForLabel("MMQ02695.ARW", fileName))

        let neighborLeft = element(app, "clove.detail.filmstrip.mmq02694")
        let neighborCurrent = element(app, "clove.detail.filmstrip.mmq02695")
        let stack = element(app, "clove.detail.filmstrip.group.burst-2696")
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), neighborCurrent))
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), stack))
        XCTAssertTrue(neighborLeft.isHittable)

        let leftBefore = neighborLeft.frame
        let currentBefore = neighborCurrent.frame
        let stackBefore = stack.frame

        // Expanding a visible group keeps neighbors put and starts the run at the stack's slot.
        stack.tap()
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", fileName))
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5))
        let firstMember = element(app, "clove.detail.filmstrip.mmq02696")
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), firstMember))
        XCTAssertEqual(neighborLeft.frame.minX, leftBefore.minX, accuracy: 2)
        XCTAssertEqual(neighborCurrent.frame.minX, currentBefore.minX, accuracy: 2)
        XCTAssertEqual(firstMember.frame.minX, stackBefore.minX + 3, accuracy: 4)

        // Tapping another visible member does not jump the strip.
        let firstMemberBeforeTap = firstMember.frame
        let secondMember = element(app, "clove.detail.filmstrip.mmq02697")
        XCTAssertTrue(secondMember.isHittable)
        secondMember.tap()
        XCTAssertTrue(waitForLabel("MMQ02697.ARW", fileName))
        XCTAssertEqual(neighborCurrent.frame.minX, currentBefore.minX, accuracy: 2)
        XCTAssertEqual(firstMember.frame.minX, firstMemberBeforeTap.minX, accuracy: 2)

        // Leaving to a visible neighbor folds the group back at the same position with no jump.
        neighborCurrent.tap()
        XCTAssertTrue(waitForLabel("MMQ02695.ARW", fileName))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.filmstrip.expandedGroup")))
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        XCTAssertEqual(neighborLeft.frame.minX, leftBefore.minX, accuracy: 2)
        XCTAssertEqual(neighborCurrent.frame.minX, currentBefore.minX, accuracy: 2)
        XCTAssertEqual(stack.frame.minX, stackBefore.minX, accuracy: 2)

        // Navigating forward to an off-screen photo via swipe brings it into view (#252, #255).
        let preview = element(app, "clove.detail.preview")
        for _ in 0..<8 {
            preview.swipeLeft()
        }
        XCTAssertTrue(waitForLabel("MMQ02703.ARW", fileName))
        let offscreenTarget = element(app, "clove.detail.filmstrip.mmq02703")
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), offscreenTarget),
            "off-screen navigation did not bring the destination thumbnail into view")
    }

    @MainActor
    func testDetailFocusRegionsCentreNativeZoom() throws {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)
        applyComparisonTheme("light", app)
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        turnOffAutoAdvance(app)
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02678").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let toggle = element(app, "clove.detail.focusToggle")
        let autofocus = element(app, "clove.detail.region.af.0")
        let eye = element(app, "clove.detail.region.face.1-0")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "On")
        XCTAssertTrue(autofocus.waitForExistence(timeout: 5))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.2-0").exists)
        capture("detail-focus-regions-fit")

        let fileName = element(app, "clove.detail.fileName").label
        let marks = element(app, "clove.detail.capsule").value as? String
        autofocus.tap()
        let zoom = element(app, "clove.detail.zoom")
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "value CONTAINS %@", "centred at 30%, 35%"), preview),
            "The region tap did not centre the existing native zoom on the AF rectangle")
        XCTAssertEqual(element(app, "clove.detail.fileName").label, fileName)
        XCTAssertTrue(autofocus.exists)
        XCTAssertFalse(eye.exists)
        capture("detail-focus-region-native-zoom")

        preview.doubleTap()
        XCTAssertFalse(zoom.label.hasSuffix("100%"))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.capsule").value as? String, marks)

        // Double-tapping the photo body away from the AF rectangle (including near the edges, #252)
        // still centres 100% on AF; a second double-tap anywhere returns to fit.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "value CONTAINS %@", "centred at 30%, 35%"), preview),
            "Double-tap should centre on the AF region instead of the tap point")
        XCTAssertTrue(autofocus.exists)
        XCTAssertFalse(eye.exists)
        preview.doubleTap()
        XCTAssertFalse(zoom.label.hasSuffix("100%"))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.capsule").value as? String, marks)

        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "value CONTAINS %@", "centred at 30%, 35%"), preview),
            "Double-tap near the edge should zoom on the preferred region rather than navigate")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).doubleTap()
        XCTAssertFalse(zoom.label.hasSuffix("100%"))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, fileName)

        let eyeSwipe = eye.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        eyeSwipe.press(
            forDuration: 0.1,
            thenDragTo: eyeSwipe.withOffset(CGVector(dx: 0, dy: 70)),
            withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, fileName)
        let eyeMarkValue = element(app, "clove.detail.capsule").value as? String
        XCTAssertTrue(
            eyeMarkValue?.contains("4 stars") == true,
            "Marks after eye swipe: \(eyeMarkValue ?? "nil")")
        let autofocusSwipe = autofocus.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        autofocusSwipe.press(
            forDuration: 0.1,
            thenDragTo: autofocusSwipe.withOffset(CGVector(dx: -160, dy: 0)))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02679.ARW")
        let tiny = element(app, "clove.detail.region.af.0")
        XCTAssertTrue(tiny.waitForExistence(timeout: 5))
        XCTAssertTrue(
            wait(NSPredicate(format: "value CONTAINS %@", "region too small"), tiny))
        tiny.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02679.ARW")
        XCTAssertFalse(zoom.label.hasSuffix("100%"))
        capture("detail-focus-region-tiny-unavailable")

        // Local AF overlap suppression & shared Off/On toggle across photo navigation.
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02683").tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let overlapAF = element(app, "clove.detail.region.af.0")
        let personOneEye = element(app, "clove.detail.region.face.4-1")
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
        XCTAssertTrue(personOneEye.exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.1-0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.3-1").exists)
        capture("detail-focus-regions-overlap-light")

        toggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), toggle))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), overlapAF))
        XCTAssertFalse(personOneEye.exists)
        capture("detail-focus-regions-off-light")

        // Navigating while Off keeps regions and status suppressed.
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02684.ARW", element(app, "clove.detail.fileName")))
        XCTAssertEqual(toggle.value as? String, "Off")
        XCTAssertFalse(element(app, "clove.detail.region.af.0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertFalse(element(app, "clove.detail.focusStatus").exists)

        // Turning On reveals AF + face fallback (four corner brackets) on MMQ02684.
        toggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), toggle))
        XCTAssertTrue(element(app, "clove.detail.region.af.0").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.region.face.0-0").exists)
        capture("detail-focus-regions-face-fallback-light")

        // Dark theme toggle contrast and overlay legibility.
        element(app, "clove.nav.back").tap()
        applyComparisonTheme("dark", app)
        element(app, "clove.grid.photo.mmq02683").tap()
        XCTAssertTrue(element(app, "clove.detail.region.af.0").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.region.face.4-1").exists)
        capture("detail-focus-regions-overlap-dark")
        toggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), toggle))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.region.af.0")))
        capture("detail-focus-regions-off-dark")

        // Photo with no focus regions keeps tap-point double-tap zoom anywhere, including edges.
        toggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), toggle))
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertFalse(element(app, "clove.detail.region.af.0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "value CONTAINS %@", "centred at 65%, 50%"), preview),
            "Double-tap on a photo with no focus regions should centre on the tap point")
        preview.doubleTap()
        XCTAssertFalse(zoom.label.hasSuffix("100%"))

        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.5)).doubleTap()
        XCTAssertFalse(zoom.label.hasSuffix("100%"))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
    }

    @MainActor
    func testTapPickersSelectionClearDismissAndOrientation() {
        let app = launchSample()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .portrait
        openLibrary(app)

        // Turn off auto-advance so clearing and labelling stay on the same photo.
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        turnOffAutoAdvance(app)
        element(app, "clove.nav.back").tap()

        // 1. Detail tap color picker (iPhone): horizontal geometry, outside-tap dismissal, select, clear, landscape.
        if UIDevice.current.userInterfaceIdiom == .phone {
            element(app, "clove.grid.photo.mmq02680").tap()
            let labelButton = element(app, "clove.detail.capsule.label")
            let capsule = element(app, "clove.detail.capsule")
            XCTAssertTrue(labelButton.waitForExistence(timeout: 5))
            rate(3, in: app)
            XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "3 stars"), capsule))

            labelButton.tap()
            let picker = element(app, "clove.detail.labels")
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertGreaterThan(picker.frame.width, picker.frame.height)
            XCTAssertGreaterThanOrEqual(picker.frame.width, 280)
            XCTAssertGreaterThanOrEqual(picker.frame.height, 48)
            XCTAssertLessThanOrEqual(picker.frame.maxX, app.frame.maxX)

            // Outside tap dismisses without toggling chrome or changing marks.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.3)).tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), picker))
            XCTAssertTrue(capsule.exists)
            XCTAssertEqual(labelButton.label, "Label")

            // Pick green, verify selection ring / state, then clear via None while keeping 3 stars.
            labelButton.tap()
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            element(app, "clove.detail.labels.green").tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), picker))
            XCTAssertEqual(labelButton.label, "Label, Green")

            labelButton.tap()
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertTrue(element(app, "clove.detail.labels.green").isSelected)
            element(app, "clove.detail.labels.none").tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), picker))
            XCTAssertEqual(labelButton.label, "Label")
            XCTAssertTrue(wait(NSPredicate(format: "value == %@", "3 stars"), capsule))

            // Rotate to landscape: floating picker stays inside safe bounds and dismisses on outside tap.
            XCUIDevice.shared.orientation = .landscapeLeft
            labelButton.tap()
            XCTAssertTrue(picker.waitForExistence(timeout: 5))
            XCTAssertGreaterThanOrEqual(picker.frame.minX, 0)
            XCTAssertLessThanOrEqual(picker.frame.maxX, app.frame.maxX)
            XCTAssertGreaterThanOrEqual(picker.frame.minY, 0)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.25)).tap()
            XCTAssertTrue(wait(NSPredicate(format: "exists == false"), picker))
            XCUIDevice.shared.orientation = .portrait

            element(app, "clove.nav.back").tap()
        }

        // 2. Mixed batch selection: mixed labels must NOT highlight None, and outside tap dismisses.
        let ratedAndRed = element(app, "clove.grid.photo.mmq02678")
        XCTAssertTrue(ratedAndRed.waitForExistence(timeout: 5))
        ratedAndRed.press(forDuration: 0.6)
        element(app, "clove.grid.photo.mmq02680").tap()

        element(app, "clove.grid.batch.label").tap()
        let batchPicker = element(app, "clove.grid.batch.labels")
        XCTAssertTrue(batchPicker.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.grid.batch.labels.none").isSelected)
        XCTAssertFalse(element(app, "clove.grid.batch.labels.red").isSelected)
        element(app, "clove.grid").coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.3))
            .tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), batchPicker))

        element(app, "clove.grid.batch.label").tap()
        XCTAssertTrue(batchPicker.waitForExistence(timeout: 5))
        element(app, "clove.grid.batch.labels.none").tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), batchPicker))
        XCTAssertFalse(ratedAndRed.label.contains("Red"))
        XCTAssertTrue(ratedAndRed.label.contains("5 stars"))
    }

    @MainActor
    func testZoomedRatingSwipeModesAndFitGestures() throws {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)

        element(app, "clove.grid.photo.mmq02680").tap()
        let preview = element(app, "clove.detail.preview")
        let fileName = element(app, "clove.detail.fileName")
        let capsule = element(app, "clove.detail.capsule")
        let zoom = element(app, "clove.detail.zoom")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertEqual(capsule.value as? String, "Unmarked")

        // Fit gestures remain unchanged in default mode.
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", fileName))
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))

        // Pinch zooms in default mode and never rates.
        preview.pinch(withScale: 2.0, velocity: 1.0)
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), capsule))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        XCTAssertEqual(capsule.value as? String, "Unmarked")

        // 1-finger pan still pans while zoomed in default mode and never rates.
        let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.doubleTap()
        XCTAssertEqual(zoom.label, "3 / 36 · 100%")
        XCTAssertFalse(capsule.exists)
        let centredBeforePan = preview.value as? String
        let panStart = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        panStart.press(
            forDuration: 0.05, thenDragTo: panStart.withOffset(CGVector(dx: 0, dy: -150)),
            withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(zoom.label, "3 / 36 · 100%")
        XCTAssertFalse(capsule.exists)
        XCTAssertNotEqual(preview.value as? String, centredBeforePan)

        // Default two-finger vertical swipe while zoomed rates, auto-advances, and returns to fit.
        try swipeTwoFingersVertically(in: preview, deltaY: -180, app: app)
        XCTAssertTrue(waitForLabel("MMQ02681.ARW", fileName, timeout: 10))
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        XCTAssertFalse(element(app, "clove.detail.swipeFeedback").exists)
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        XCTAssertTrue((capsule.value as? String)?.contains("stars") == true)

        // Switch setting to single-finger axis lock.
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        openSettingsCategory("clove.settings.category.culling", in: app)
        let zoomedSwipeSetting = element(app, "clove.settings.zoomedRatingSwipe")
        for _ in 0..<8 {
            if zoomedSwipeSetting.exists && zoomedSwipeSetting.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(zoomedSwipeSetting.isHittable)
        zoomedSwipeSetting.tap()
        app.buttons["Single-finger axis lock"].tap()
        XCTAssertTrue(
            String(describing: zoomedSwipeSetting.value).contains("Single-finger axis lock")
                || zoomedSwipeSetting.label.contains("Single-finger axis lock"))
        element(app, "clove.nav.back").tap()

        // Open standalone unrated photo MMQ02682.ARW in axis-lock mode.
        let standalone = element(app, "clove.grid.photo.mmq02682")
        XCTAssertTrue(standalone.waitForExistence(timeout: 5))
        standalone.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let initialAxisLockMarks = capsule.value as? String
        XCTAssertEqual(initialAxisLockMarks, "Green")

        // Fit horizontal navigation still works cleanly with axis-lock zoomed setting active.
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02683.ARW", fileName))
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))

        // Pinch still zooms in axis-lock mode and never rates.
        preview.pinch(withScale: 2.0, velocity: 1.0)
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), capsule))
        XCTAssertEqual(fileName.label, "MMQ02682.ARW")
        centre.doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        XCTAssertEqual(capsule.value as? String, initialAxisLockMarks)

        // Zoom to 100%: horizontal drag pans without navigating or rating; vertical drag rates +
        // auto-advances + returns to fit.
        centre.doubleTap()
        XCTAssertEqual(zoom.label, "5 / 36 · 100%")
        XCTAssertFalse(capsule.exists)
        let centredBeforeHorizontalPan = preview.value as? String
        preview.swipeLeft()
        XCTAssertEqual(fileName.label, "MMQ02682.ARW")
        XCTAssertFalse(capsule.exists)
        XCTAssertNotEqual(preview.value as? String, centredBeforeHorizontalPan)

        let verticalStart = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        verticalStart.press(
            forDuration: 0.02, thenDragTo: verticalStart.withOffset(CGVector(dx: 0, dy: -180)),
            withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(waitForLabel("MMQ02683.ARW", fileName, timeout: 10))
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        XCTAssertFalse(element(app, "clove.detail.swipeFeedback").exists)
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
        XCTAssertTrue((capsule.value as? String)?.contains("stars") == true)
    }

    @MainActor
    private func swipeTwoFingersVertically(
        in element: XCUIElement, deltaY: CGFloat, app: XCUIApplication
    ) throws {
        guard
            let pathClass = NSClassFromString("XCPointerEventPath") as? NSObject.Type,
            let recordClass = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type
        else {
            XCTFail("XCTAutomationSupport multi-touch synthesis classes are unavailable")
            return
        }
        let allocSel = NSSelectorFromString("alloc")
        let initTouchSel = NSSelectorFromString("initForTouchAtPoint:offset:")
        let moveSel = NSSelectorFromString("moveToPoint:atOffset:")
        let liftSel = NSSelectorFromString("liftUpAtOffset:")
        let initRecordSel = NSSelectorFromString("initWithName:interfaceOrientation:")
        let addPathSel = NSSelectorFromString("addPointerEventPath:")
        let synthesizeErrorSel = NSSelectorFromString("synthesizeWithError:")

        typealias AllocIMP = @convention(c) (AnyClass, Selector) -> AnyObject
        typealias InitTouchIMP =
            @convention(c) (
                AnyObject, Selector, CGPoint, TimeInterval
            ) -> AnyObject
        typealias MoveIMP = @convention(c) (AnyObject, Selector, CGPoint, TimeInterval) -> Void
        typealias LiftIMP = @convention(c) (AnyObject, Selector, TimeInterval) -> Void
        typealias InitRecordIMP = @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
        typealias AddPathIMP = @convention(c) (AnyObject, Selector, AnyObject) -> Void
        typealias SynthesizeErrorIMP =
            @convention(c) (AnyObject, Selector, UnsafeMutablePointer<NSError?>?) -> Bool

        let allocPath = unsafeBitCast(
            class_getMethodImplementation(object_getClass(pathClass), allocSel), to: AllocIMP.self)
        let initTouch = unsafeBitCast(
            class_getMethodImplementation(pathClass, initTouchSel), to: InitTouchIMP.self)
        let moveTo = unsafeBitCast(
            class_getMethodImplementation(pathClass, moveSel), to: MoveIMP.self)
        let liftUp = unsafeBitCast(
            class_getMethodImplementation(pathClass, liftSel), to: LiftIMP.self)

        let allocRecord = unsafeBitCast(
            class_getMethodImplementation(object_getClass(recordClass), allocSel),
            to: AllocIMP.self)
        let initRecord = unsafeBitCast(
            class_getMethodImplementation(recordClass, initRecordSel), to: InitRecordIMP.self)
        let addPath = unsafeBitCast(
            class_getMethodImplementation(recordClass, addPathSel), to: AddPathIMP.self)
        let synthesizeWithError = unsafeBitCast(
            class_getMethodImplementation(recordClass, synthesizeErrorSel),
            to: SynthesizeErrorIMP.self)

        let frame = element.frame
        let startY = frame.midY + (deltaY < 0 ? 80 : -80)
        let leftStart = CGPoint(x: frame.midX - 35, y: startY)
        let rightStart = CGPoint(x: frame.midX + 35, y: startY)

        let leftPath = initTouch(allocPath(pathClass, allocSel), initTouchSel, leftStart, 0.0)
        let rightPath = initTouch(allocPath(pathClass, allocSel), initTouchSel, rightStart, 0.0)
        let steps = 12
        let duration: TimeInterval = 0.6
        for step in 1...steps {
            let fraction = CGFloat(step) / CGFloat(steps)
            let offset = 0.05 + duration * Double(fraction)
            moveTo(
                leftPath, moveSel,
                CGPoint(x: leftStart.x, y: leftStart.y + deltaY * fraction), offset)
            moveTo(
                rightPath, moveSel,
                CGPoint(x: rightStart.x, y: rightStart.y + deltaY * fraction), offset)
        }
        // Stagger release slightly to verify first-finger-lift termination cleanly commits.
        liftUp(leftPath, liftSel, 0.72)
        liftUp(rightPath, liftSel, 0.76)

        let rawOrientation = XCUIDevice.shared.orientation.rawValue
        let orientation = rawOrientation == 0 ? 1 : rawOrientation
        let record = initRecord(
            allocRecord(recordClass, allocSel), initRecordSel,
            "Two-finger vertical swipe" as NSString, orientation)
        addPath(record, addPathSel, leftPath)
        addPath(record, addPathSel, rightPath)

        var error: NSError?
        let ok = synthesizeWithError(record, synthesizeErrorSel, &error)
        XCTAssertTrue(ok, "Two-finger swipe synthesis failed: \(String(describing: error))")
        XCTAssertNil(error)
    }

    @MainActor
    func testCaptureTapPickerReferencesWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_TAP_PICKERS"] == "1")
        defer { XCUIDevice.shared.orientation = .portrait }

        // 1. Design gallery across Light, Dark, and Nord (values 0–5, rejected, disabled, mixed, vertical, all labels).
        let gallery = launchSample(["CLOVE_DESIGN_GALLERY": "1"])
        for theme in ["light", "dark", "nord"] {
            element(gallery, "clove.design.gallery.theme.\(theme)").tap()
            let scroll = gallery.scrollViews.firstMatch
            let ratingAnchor = element(gallery, "clove.mark.ratingPicker")
            for _ in 0..<4 where !ratingAnchor.isHittable { scroll.swipeUp() }
            capture("gallery-tap-pickers-rating-\(theme)")
            let labelAnchor = element(gallery, "clove.design.gallery.labelPicker.vertical")
            for _ in 0..<4 where !labelAnchor.isHittable { scroll.swipeUp() }
            capture("gallery-tap-pickers-label-\(theme)")
            for _ in 0..<6 where !element(gallery, "clove.design.gallery.theme.\(theme)").isHittable
            {
                scroll.swipeDown()
            }
        }
        gallery.terminate()

        // 2. Detail + Mixed Batch on real screen (Light, Dark, Portrait & Landscape).
        for theme in ["light", "dark"] {
            let app = launchSample()
            openLibrary(app)
            applyComparisonTheme(theme, app)
            if theme == "light" {
                let rated = element(app, "clove.grid.photo.mmq02678")
                rated.press(forDuration: 0.6)
                element(app, "clove.grid.photo.mmq02680").tap()
                element(app, "clove.grid.batch.label").tap()
                XCTAssertTrue(element(app, "clove.grid.batch.labels").waitForExistence(timeout: 5))
                capture("grid-batch-labels-mixed-\(theme)")
                element(app, "clove.grid").coordinate(
                    withNormalizedOffset: CGVector(dx: 0.65, dy: 0.3)
                )
                .tap()
                element(app, "clove.grid.batch.done").tap()
            }
            element(app, "clove.grid.photo.mmq02680").tap()
            if UIDevice.current.userInterfaceIdiom == .phone {
                element(app, "clove.detail.capsule.label").tap()
                XCTAssertTrue(element(app, "clove.detail.labels").waitForExistence(timeout: 5))
                capture("detail-labels-portrait-\(theme)")
                if theme == "light" {
                    XCUIDevice.shared.orientation = .landscapeLeft
                    XCTAssertTrue(element(app, "clove.detail.labels").waitForExistence(timeout: 5))
                    capture("detail-labels-landscape-\(theme)")
                    XCUIDevice.shared.orientation = .portrait
                }
            } else {
                capture("ipad-rail-\(theme)")
            }
            app.terminate()
        }
    }

    @MainActor
    func launchSample(_ environment: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment = ["CLOVE_TEST_LIBRARY": "1"].merging(environment) { _, new in new }
        app.launch()
        let root =
            environment["CLOVE_DESIGN_GALLERY"] == "1" ? "clove.design.gallery" : "clove.root"
        XCTAssertTrue(element(app, root).waitForExistence(timeout: 30))
        return app
    }

    @MainActor
    func openLibrary(_ app: XCUIApplication) {
        let open = element(app, "clove.entry.openFolder")
        if open.exists { open.tap() }
        if element(app, "clove.detail").exists {
            let back = element(app, "clove.nav.back")
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 10))
    }

    @MainActor
    private func chooseCollapsedGrid(_ app: XCUIApplication) {
        openSettingsCategory("clove.settings.category.browsing", in: app)
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
    func waitForLabel(
        _ label: String, _ target: XCUIElement, timeout: TimeInterval = 5
    ) -> Bool {
        wait(NSPredicate(format: "label == %@", label), target, timeout: timeout)
    }

    /// Opens the marking toolbar's rating ladder and taps a level: the compact toolbar's rating
    /// action is a popover trigger, so tests reach the stars through it (#227).
    @MainActor
    func rate(_ level: Int, toolbar: String = "clove.detail.capsule", in app: XCUIApplication) {
        element(app, "\(toolbar).rating").tap()
        let star = element(app, "\(toolbar).stars.\(level)")
        XCTAssertTrue(star.waitForExistence(timeout: 5), "the rating ladder did not open")
        star.tap()
    }

    /// Drags the filmstrip one viewport towards its end and waits for the scroll to settle, so
    /// the strip's lazy cells materialize as the offset advances and the read that follows sees
    /// the content's real extent, not a programmatic jump's estimate (#237).
    @MainActor
    private func dragStripForward(_ strip: XCUIElement) {
        let start = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5))
        start.press(
            forDuration: 0.05,
            thenDragTo: strip.coordinate(withNormalizedOffset: CGVector(dx: 0.2, dy: 0.5)),
            withVelocity: .slow, thenHoldForDuration: 0)
        Thread.sleep(forTimeInterval: 0.3)
    }

    /// Whether a filmstrip cell is on screen and flush with the strip's trailing edge, within
    /// one thumbnail's width: the position the strip's content rests at when it fills its
    /// viewport (#237).
    @MainActor
    private func restsAtTrailingEdge(_ cell: XCUIElement, of strip: XCUIElement) -> Bool {
        guard cell.exists else { return false }
        let frame = cell.frame
        let edge = strip.frame.maxX
        return frame.maxX <= edge && frame.maxX >= edge - 27 && frame.minX >= strip.frame.minX
    }

    /// Swipes the filmstrip until the thumbnail is on screen, bounded, because a lazy strip does
    /// not build its far entries until they scroll near. `forward` swipes towards the strip's
    /// trailing end; the caller picks the direction from the current photo (#237).
    @MainActor
    func swipeStripUntilHittable(
        _ identifier: String, in app: XCUIApplication, forward: Bool = true
    ) -> XCUIElement {
        let target = element(app, identifier)
        let strip = element(app, "clove.detail.filmstrip")
        for _ in 0..<12 where !target.isHittable {
            if forward {
                strip.swipeLeft(velocity: .fast)
            } else {
                strip.swipeRight(velocity: .fast)
            }
        }
        XCTAssertTrue(target.isHittable, "the strip never brought \(identifier) on screen")
        return target
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
