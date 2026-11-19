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
            chooseTheme(theme, app)
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
        // Wide iPad opens in Photo Preview (30% filtered grid beside photo, no filmstrip).
        let splitGrid = element(app, "clove.detail.photoGrid")
        let gridToggle = element(app, "clove.detail.gridToggle")
        XCTAssertTrue(splitGrid.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.detail.filmstrip").exists)
        XCTAssertTrue(gridToggle.exists)
        XCTAssertEqual(gridToggle.label, "Hide photo grid")
        XCTAssertEqual(gridToggle.value as? String, "Photo Preview")
        gridToggle.tap()
        XCTAssertTrue(element(app, "clove.detail.filmstrip").waitForExistence(timeout: 5))
        XCTAssertFalse(splitGrid.exists)
        XCTAssertEqual(gridToggle.label, "Show photo grid")
        XCTAssertEqual(gridToggle.value as? String, "Focus View")
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
        let splitGrid = element(app, "clove.detail.photoGrid")
        let gridToggle = element(app, "clove.detail.gridToggle")
        let undoButton = element(app, "clove.detail.undo")
        XCTAssertTrue(rail.exists)
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertEqual(rail.frame.width, 96, accuracy: 1)
        // iPad opens in Photo Preview (30% folder grid + 70% photo stage, no filmstrip).
        XCTAssertTrue(splitGrid.waitForExistence(timeout: 5))
        XCTAssertFalse(strip.exists)
        XCTAssertTrue(gridToggle.exists)
        XCTAssertEqual(gridToggle.label, "Hide photo grid")
        XCTAssertEqual(gridToggle.value as? String, "Photo Preview")
        XCTAssertEqual(splitGrid.frame.width / app.frame.width, 0.3, accuracy: 0.03)
        XCTAssertLessThanOrEqual(
            element(app, "clove.nav.back").frame.maxX, gridToggle.frame.minX + 1)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        stars.tap()
        XCTAssertTrue(stars.isSelected)
        capture("ipad-detail-photo-preview-light")

        // Toggle to Focus View: same photo, marks, and Undo stay intact; filmstrip appears.
        gridToggle.tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertFalse(splitGrid.exists)
        XCTAssertEqual(gridToggle.label, "Show photo grid")
        XCTAssertEqual(gridToggle.value as? String, "Focus View")
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        XCTAssertTrue(stars.isSelected)
        XCTAssertTrue(undoButton.isEnabled)
        XCTAssertLessThanOrEqual(strip.frame.maxX, rail.frame.minX + 1)
        undoButton.tap()
        XCTAssertFalse(stars.isSelected)

        // Toggle back to Photo Preview, step to another photo, then return to Focus View to
        // verify presentation preference persists across photo navigation in Focus View.
        gridToggle.tap()
        XCTAssertTrue(splitGrid.waitForExistence(timeout: 5))
        XCTAssertFalse(strip.exists)
        gridToggle.tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        element(app, "clove.detail.filmstrip.mmq02682").tap()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", element(app, "clove.detail.fileName")))
        XCTAssertTrue(strip.exists)
        XCTAssertFalse(splitGrid.exists)
        element(app, "clove.detail.filmstrip.mmq02680").tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", element(app, "clove.detail.fileName")))

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
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "2 / 32 · 100%")
        XCTAssertTrue(strip.exists)
        // Chrome is one visibility across fit and zoom (#302).
        XCTAssertTrue(element(app, "clove.detail.info").exists)
        XCTAssertTrue(rail.isHittable)
        XCTAssertEqual(preview.frame, stageFrame)
        // Toggling to Photo Preview while zoomed preserves zoom at 100%, then back to Focus View.
        gridToggle.tap()
        XCTAssertTrue(splitGrid.waitForExistence(timeout: 5))
        XCTAssertFalse(strip.exists)
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "2 / 32 · 100%")
        gridToggle.tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertFalse(splitGrid.exists)
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "2 / 32 · 100%")
        // Single-tapping while zoomed toggles the filmstrip without stepping photos.
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), strip))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "2 / 32 · 100%")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        // Swiping/dragging on the filmstrip while zoomed must not pan the photo or rate via swipe.
        let zoomedPosition = preview.value as? String
        let railMarksBeforeStrip = rail.value as? String
        strip.swipeLeft()
        XCTAssertEqual(preview.value as? String, zoomedPosition)
        XCTAssertEqual(rail.value as? String, railMarksBeforeStrip)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        let stripVertical = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        stripVertical.press(
            forDuration: 0.05, thenDragTo: stripVertical.withOffset(CGVector(dx: 0, dy: -200)))
        XCTAssertEqual(rail.value as? String, railMarksBeforeStrip)
        XCTAssertEqual(preview.value as? String, zoomedPosition)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        // Double-tapping near an edge/corner returns to fit without stepping.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.85)).doubleTap()
        // The fit that restores the chrome lands after the double tap returns (#203).
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
        let info = element(app, "clove.detail.info")
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), info))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        // Corner and edge single taps at fit toggle chrome and never step photos.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.08)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), strip))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
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
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
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
        XCTAssertTrue(splitGrid.waitForExistence(timeout: 5))
        capture("ipad-detail-photo-preview-dark")
        gridToggle.tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        capture("ipad-detail-rail-dark")
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02683").tap()
        let focusToggle = element(app, "clove.detail.focusToggle")
        let overlapAF = element(app, "clove.detail.region.af.0")
        let separatedEye = element(app, "clove.detail.region.face.4-1")
        let focusIndicators = element(app, "clove.detail.focusIndicators")
        let faceIndicator = element(app, "clove.detail.focusIndicator.face")
        let missingAFIndicator = element(app, "clove.detail.focusIndicator.autofocus")
        XCTAssertTrue(focusToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(focusToggle.value as? String, "On")
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
        XCTAssertTrue(separatedEye.exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.1-0").exists)
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "Face detected")
        XCTAssertFalse(missingAFIndicator.exists)
        // Corner tap & double-tap on a focus-region photo never step photos and keep filmstrip at zoom.
        gridToggle.tap()
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.08)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), strip))
        XCTAssertFalse(focusIndicators.exists)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02683.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.08)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.4)).doubleTap()
        XCTAssertTrue(element(app, "clove.detail.zoom").label.contains("100%"))
        XCTAssertTrue(strip.exists)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02683.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.4)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), info))
        XCTAssertEqual(app.buttons.matching(identifier: "clove.detail.focusToggle").count, 1)
        capture("ipad-detail-focus-on")
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), focusToggle))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), overlapAF))
        XCTAssertFalse(separatedEye.exists)
        XCTAssertFalse(focusIndicators.exists)
        capture("ipad-detail-focus-off")
        gridToggle.tap()
        XCTAssertTrue(splitGrid.waitForExistence(timeout: 5))
        XCTAssertEqual(focusToggle.value as? String, "Off")
        XCTAssertFalse(overlapAF.exists)
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02684.ARW", element(app, "clove.detail.fileName")))
        XCTAssertEqual(focusToggle.value as? String, "Off")
        XCTAssertFalse(overlapAF.exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertFalse(focusIndicators.exists)
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), focusToggle))
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "Face detected")
        XCTAssertFalse(missingAFIndicator.exists)
        app.terminate()
        checkDisabledRail()
    }

    /// #305 on iPad: the pill floats over the stage in Photo Preview and Focus View alike, so the
    /// stage keeps its frame while the pill's availability and the fit–zoom transitions change.
    @MainActor
    func testIPadFinishingPillNeverResizesTheStage() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = launchSample()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        openLibrary(app)
        element(app, "clove.grid.group.burst-2678").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let pill = element(app, "clove.detail.rejectUnmarked")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.detail.filmstrip").exists)
        // Photo Preview has no filmstrip: the pill floats 12 pt above the stage's bottom edge.
        XCTAssertEqual(pill.frame.minY, preview.frame.maxY - 12 - pill.frame.height, accuracy: 1)
        XCTAssertTrue(pill.isHittable)

        // Focus View replaces the 30/70 split with the full stage and the strip under it, which is
        // its own presentation; from there the stage must not move again (#305).
        element(app, "clove.detail.gridToggle").tap()
        let strip = element(app, "clove.detail.filmstrip")
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        let focusStage = preview.frame
        XCTAssertLessThanOrEqual(pill.frame.maxY, strip.frame.minY)
        XCTAssertTrue(pill.isHittable)

        // 100% zoom and then finishing never resize this stage, and the pill stays above the strip.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(
            wait(NSPredicate(format: "value BEGINSWITH %@", "Loaded, centred at"), preview))
        assertSameFrame(preview.frame, focusStage, "zoom resized the iPad stage")
        XCTAssertLessThanOrEqual(pill.frame.maxY, strip.frame.minY)
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        pill.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), pill))
        assertSameFrame(preview.frame, focusStage, "finishing resized the iPad stage")
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
        chooseTheme(theme, app)
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

    /// #309: Photo Preview's split grid isolates the active group the same way Focus View's
    /// filmstrip does. Opening a stack shows only that group's visible members, choosing a member
    /// keeps Group Focus, folding returns to the folder on the group's Representative Photo, and
    /// opening the other group scopes the pane to it.
    @MainActor
    func testIPadPhotoPreviewGroupFocusIsolatesTheActiveGroup() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad)
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()

        let splitGrid = element(app, "clove.detail.photoGrid")
        XCTAssertTrue(splitGrid.waitForExistence(timeout: 5))
        let gridCollection = splitGrid.collectionViews.firstMatch
        XCTAssertTrue(gridCollection.waitForExistence(timeout: 5))
        let fileName = element(app, "clove.detail.fileName")
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")

        // Timeline keeps the folder's own photos and its collapsed stacks.
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02680").exists)
        XCTAssertTrue(element(app, "clove.grid.group.burst-2678").exists)
        let stack = element(app, "clove.grid.group.burst-2696")
        for _ in 0..<8 where !(stack.exists && stack.isHittable) {
            gridCollection.swipeUp()
        }
        XCTAssertTrue(stack.isHittable, "burst-2696 never scrolled into the split pane")
        stack.tap()

        // Group Focus draws only burst-2696's visible members, with its count header and fold.
        let count = element(app, "clove.grid.group.count.burst-2696")
        let fold = element(app, "clove.grid.group.fold")
        let first = element(app, "clove.grid.photo.mmq02696")
        let third = element(app, "clove.grid.photo.mmq02698")
        XCTAssertTrue(count.waitForExistence(timeout: 5))
        XCTAssertEqual(count.label, "3 photos")
        XCTAssertTrue(fold.isHittable)
        XCTAssertTrue(first.waitForExistence(timeout: 5))
        XCTAssertTrue(third.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02695").exists)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02699").exists)
        XCTAssertFalse(element(app, "clove.grid.group.burst-2678").exists)
        XCTAssertEqual(fileName.label, "MMQ02696.ARW")
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(third.isSelected)
        capture("ipad-photo-preview-group-focus")

        // Choosing another member changes the photo without leaving Group Focus.
        third.tap()
        XCTAssertTrue(waitForLabel("MMQ02698.ARW", fileName))
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == true"), third))
        XCTAssertTrue(count.exists)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02699").exists)
        // A mark stays with the member and is readable in the split grid.
        element(app, "clove.detail.rail.stars.4").tap()
        XCTAssertTrue(wait(NSPredicate(format: "label CONTAINS %@", "4 stars"), third))

        // Folding returns to the full folder Timeline on the Representative Photo (the rated
        // member) with the group's stack holding it.
        fold.tap()
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel("MMQ02698.ARW", fileName))
        XCTAssertTrue(stack.isSelected)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02696").exists)
        // The whole folder is back above and below the stack.
        let firstGroup = element(app, "clove.grid.group.burst-2678")
        for _ in 0..<8 where !(firstGroup.exists && firstGroup.isHittable) {
            gridCollection.swipeDown()
        }
        XCTAssertTrue(firstGroup.isHittable, "burst-2678 never scrolled into the split pane")
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02680").exists)
        capture("ipad-photo-preview-group-folded")

        // Opening the other group scopes the pane to that group only.
        firstGroup.tap()
        XCTAssertTrue(
            element(app, "clove.grid.group.count.burst-2678").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02678").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02679").exists)
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02681").exists)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02680").exists)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02696").exists)
        XCTAssertFalse(element(app, "clove.grid.group.burst-2696").exists)
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", fileName))

        // Folding the second group also lands on its Representative Photo in Timeline.
        element(app, "clove.grid.group.fold").tap()
        XCTAssertTrue(
            element(app, "clove.grid.group.burst-2678").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", fileName))
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02678").exists)
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
        XCTAssertEqual(fileName.label, "MMQ02682.ARW")
        app.typeKey("z", modifierFlags: .command)
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(capsule.value as? String, "3 stars")
        element(app, "clove.detail.info").tap()
        element(app, "clove.detail.info.done").tap()
        app.typeKey("0", modifierFlags: [])
        XCTAssertEqual(capsule.value as? String, "Unmarked")
    }

    @MainActor
    func testDriveLossDropsTheRequestedMarkAndDisablesMarking() {
        let app = launchSample([
            "CLOVE_TEST_LIBRARY_DISCONNECT_ON_WRITE": "1",
            "CLOVE_TEST_LIBRARY_WRITE_DELAY_MS": "500",
        ])
        defer { app.terminate() }
        openLibrary(app)
        element(app, "clove.grid.photo.mmq02680").tap()
        let label = element(app, "clove.detail.capsule.label")
        label.tap()
        element(app, "clove.detail.labels.red").tap()
        XCTAssertTrue(waitForLabel("Not connected", element(app, "clove.detail.saveState")))
        XCTAssertTrue(element(app, "clove.detail.saveStatus.failure.action").exists)
        XCTAssertFalse(element(app, "clove.save.toast").exists)
        XCTAssertEqual(label.label, "Label")
        XCTAssertFalse(label.isEnabled)
        element(app, "clove.nav.back").tap()
        XCTAssertEqual(element(app, "clove.grid.saveState").label, "Not connected")
        XCTAssertTrue(app.staticTexts["The drive disconnected."].exists)
        XCTAssertTrue(element(app, "clove.grid.saveState.failure.action").exists)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02680").label.contains("Red"))
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
        let isRail = element(app, "clove.detail.rail").exists
        let marksControl = element(app, isRail ? "clove.detail.rail" : "clove.detail.capsule")
        let strip = element(app, "clove.detail.filmstrip")
        let chromeTarget = isRail ? strip : marksControl
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
        XCTAssertEqual(fileName.label, "MMQ02682.ARW")
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
        if isRail {
            element(app, "clove.detail.rail.label.green").tap()
        } else {
            element(app, "clove.detail.capsule.label").tap()
            element(app, "clove.detail.labels.green").tap()
            XCTAssertFalse(element(app, "clove.detail.labels").exists)
        }
        let preview = navigationPreview
        let zoom = element(app, "clove.detail.zoom")
        let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.doubleTap()
        XCTAssertEqual(zoom.label, "2 / 32 · 100%")
        // Chrome is one visibility across fit and zoom: the marking controls, Info, Undo and the
        // filmstrip all stay put until a single tap hides them (#302).
        if !isRail {
            XCTAssertTrue(element(app, "clove.detail.capsule").exists)
        }
        XCTAssertTrue(element(app, "clove.detail.info").exists)
        XCTAssertTrue(element(app, "clove.detail.undo").exists)
        XCTAssertTrue(strip.exists)
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), strip))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), strip))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        // Filmstrip interactions while zoomed do not pan the preview or trigger rating swipes.
        let zoomedPosition = preview.value as? String
        let marksBeforeStrip = isRail ? (marksControl.value as? String) : nil
        strip.swipeLeft()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(preview.value as? String, zoomedPosition)
        let stripVertical = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        stripVertical.press(
            forDuration: 0.05, thenDragTo: stripVertical.withOffset(CGVector(dx: 0, dy: -200)))
        if isRail {
            XCTAssertEqual(marksControl.value as? String, marksBeforeStrip)
        }
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(preview.value as? String, zoomedPosition)
        // A horizontal drag while zoomed switches photos in the default mode, and a photo outside
        // the group opens at fit (#302).
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
        XCTAssertFalse(zoom.label.contains("100%"))
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        // The fit animation restores the chrome after the double tap returns, so this reads
        // the observed state instead of asserting one immediate snapshot.
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), info))
        XCTAssertTrue(strip.exists)
        XCTAssertEqual(marksControl.value as? String, "Green")
        // Single taps anywhere (centre or outer edges) toggle chrome after waiting for double-tap
        // and never navigate.
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), chromeTarget))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), chromeTarget))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), chromeTarget))
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.94, dy: 0.4)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), chromeTarget))
        if isRail {
            element(app, "clove.detail.rail.stars.4").tap()
        } else {
            rate(4, in: app)
        }
        // A mark waits out the advance pause before the file name changes. On a loaded runner
        // one accessibility query can consume most of a short window while the app is already
        // correct (#203), so this boundary keeps the 10-second budget the browsing flow uses.
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName, timeout: 10))
        preview.swipeRight()
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertTrue(String(describing: marksControl.value).contains("4"))
        for (_, horizontalStart, nextPhoto) in [
            ("right", 0.8, "MMQ02682.ARW"),
            // Standalone Timeline swipe-mark moves to the next standalone Timeline slot.
            ("left-third", 0.2, "MMQ02683.ARW"),
        ] {
            let start = preview.coordinate(
                withNormalizedOffset: CGVector(dx: horizontalStart, dy: 0.5))
            let end = start.withOffset(CGVector(dx: 0, dy: -130))
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
        let capsule = element(app, "clove.detail.capsule")
        let start = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.45))

        // Unrated -> slow down past rejectTravel rejects immediately (no 120pt dead band).
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 95)),
            withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0)
        XCTAssertTrue((capsule.value as? String)?.contains("Rejected") == true)
        element(app, "clove.detail.undo").tap()
        XCTAssertEqual(capsule.value as? String, "Unmarked")

        // Unrated -> up reaches 5 stars across full upSpan, then undo.
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -150)),
            withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0)
        XCTAssertTrue((capsule.value as? String)?.contains("5 stars") == true)
        element(app, "clove.detail.undo").tap()
        XCTAssertEqual(capsule.value as? String, "Unmarked")

        // Unrated -> up raises stars symmetrically to 3 stars.
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: -90)),
            withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0)
        XCTAssertTrue((capsule.value as? String)?.contains("3 stars") == true)

        // From 3 stars, slow first downward step clears to Unmarked (independent of speed).
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 52)),
            withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0)
        XCTAssertEqual(capsule.value as? String, "Unmarked")
        element(app, "clove.detail.undo").tap()
        XCTAssertTrue((capsule.value as? String)?.contains("3 stars") == true)

        // From 3 stars, fast first downward step also clears to Unmarked.
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 52)),
            withVelocity: XCUIGestureVelocity(rawValue: 1200), thenHoldForDuration: 0)
        XCTAssertEqual(capsule.value as? String, "Unmarked")
        element(app, "clove.detail.undo").tap()
        XCTAssertTrue((capsule.value as? String)?.contains("3 stars") == true)

        // From 3 stars, second downward step (>= clearTravel + rejectTravel) rejects regardless of speed.
        start.press(
            forDuration: 0.01, thenDragTo: start.withOffset(CGVector(dx: 0, dy: 135)),
            withVelocity: XCUIGestureVelocity(rawValue: 100), thenHoldForDuration: 0)
        XCTAssertTrue((capsule.value as? String)?.contains("Rejected") == true)
        XCTAssertFalse(element(app, "clove.detail.swipeFeedback").exists)
    }

    @MainActor
    func testRejectedDetailGlyphWithChromeShownAndHidden() throws {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)
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
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
        preview.swipeRight()
        XCTAssertEqual(preview.label, "MMQ02680.ARW, Rejected")
        let rejectedCorner = try rejectGlyphPixels(in: preview)
        XCTAssertNotEqual(rejectedCorner, unmarkedCorner)
        XCTAssertTrue(glyph.exists)
        let glyphFrame = glyph.frame
        capture("detail-rejected-chrome-shown")
        let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), capsule))
        XCTAssertTrue(glyph.exists)
        XCTAssertEqual(glyph.frame, glyphFrame)
        XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
        capture("detail-rejected-chrome-hidden")
        centre.doubleTap()
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "2 / 32 · 100%")
        XCTAssertTrue(glyph.exists)
        XCTAssertEqual(glyph.frame, glyphFrame)
        XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
        // A two-finger drag pans the zoomed image in the default mode without switching or
        // marking, and the glyph stays put with it.
        try swipeTwoFingersVertically(in: preview, deltaY: -120, app: app)
        XCTAssertTrue(glyph.exists)
        XCTAssertEqual(glyph.frame, glyphFrame)
        XCTAssertEqual(try rejectGlyphPixels(in: preview), rejectedCorner)
        centre.doubleTap()
        centre.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        reject.tap()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
        preview.swipeRight()
        XCTAssertEqual(preview.label, "MMQ02680.ARW")
        XCTAssertFalse(glyph.exists)
        XCTAssertEqual(try rejectGlyphPixels(in: preview), unmarkedCorner)
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
        XCTAssertEqual(element(app, "clove.detail.zoom").label, "2 / 32 · 100%")
    }

    /// #305: the finishing pill is not part of the filmstrip's layout, so its availability and the
    /// fit–zoom transitions never resize the stage or move the fitted photo. It floats above the
    /// strip, where the rest of the chrome already is, and every control it shares that band with
    /// stays usable; finishing Undo restores the pill and its unmarked member in one step.
    @MainActor
    func testFinishingPillNeverResizesTheStage() {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)
        let group = element(app, "clove.grid.group.burst-2678")
        group.tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let pill = element(app, "clove.detail.rejectUnmarked")
        XCTAssertTrue(pill.waitForExistence(timeout: 5), "no finishing pill")
        let strip = element(app, "clove.detail.filmstrip")
        let capsule = element(app, "clove.detail.capsule")
        let stage = preview.frame
        XCTAssertLessThanOrEqual(pill.frame.maxY, strip.frame.minY)
        XCTAssertLessThanOrEqual(strip.frame.maxY, capsule.frame.minY)
        XCTAssertTrue(pill.isHittable)
        XCTAssertTrue(strip.isHittable)
        XCTAssertTrue(capsule.isHittable)

        // 100% zoom keeps the stage and the pill's band, and the pill stays usable (#302, #305).
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(
            wait(NSPredicate(format: "value BEGINSWITH %@", "Loaded, centred at"), preview))
        assertSameFrame(preview.frame, stage, "zoom resized the stage")
        XCTAssertLessThanOrEqual(pill.frame.maxY, strip.frame.minY)
        XCTAssertTrue(pill.isHittable)

        // Fit again, then finish the group: the pill goes and the stage and strip stay put.
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let pillLabel = pill.label
        pill.tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), pill))
        assertSameFrame(preview.frame, stage, "finishing resized the stage")
        XCTAssertTrue(strip.exists)

        // Detail Undo restores the finished photo and its finishing pill in one step; returning to
        // Grid clears Detail Undo.
        element(app, "clove.detail.undo").tap()
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        XCTAssertEqual(pill.label, pillLabel)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02678.ARW")
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(group.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.detail.undo").exists)
    }

    /// #305: the failure toast sits in the stage's floating band above the filmstrip and below the
    /// capsule, never shows a spurious action, and restores the failed mark while keeping the pill
    /// usable in Group Focus.
    @MainActor
    func testFinishingPillAndSaveFailureToastStayUsable() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_FAIL_STEMS": "2678"])
        defer { app.terminate() }
        openLibrary(app)
        element(app, "clove.grid.group.burst-2678").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let stage = preview.frame
        // A keeper whose write saves makes the finishing action available; the failing member then
        // brings the toast while the pill is still offered.
        element(app, "clove.detail.filmstrip.mmq02679").tap()
        let label = element(app, "clove.detail.capsule.label")
        label.tap()
        element(app, "clove.detail.labels.green").tap()
        let pill = element(app, "clove.detail.rejectUnmarked")
        XCTAssertTrue(pill.waitForExistence(timeout: 5))
        element(app, "clove.detail.filmstrip.mmq02678").tap()
        XCTAssertEqual(label.label, "Label, Red")
        label.tap()
        element(app, "clove.detail.labels.green").tap()
        XCTAssertTrue(app.staticTexts["Couldn't save the mark."].waitForExistence(timeout: 5))
        let toast = element(app, "clove.save.toast")
        let filmstrip = element(app, "clove.detail.filmstrip")
        let capsule = element(app, "clove.detail.capsule")
        XCTAssertTrue(toast.exists)
        XCTAssertLessThan(toast.frame.midY, filmstrip.frame.minY)
        XCTAssertLessThan(toast.frame.maxY, capsule.frame.minY)
        XCTAssertTrue(waitForLabel("Label, Red", label))
        XCTAssertFalse(element(app, "clove.detail.saveState").exists)
        XCTAssertFalse(element(app, "clove.save.toast.action").exists)
        XCTAssertTrue(pill.exists, "the keeper keeps the finishing pill available")
        XCTAssertTrue(pill.isHittable)
        XCTAssertTrue(filmstrip.isHittable)
        assertSameFrame(preview.frame, stage, "the toast resized the stage")
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
    func testDesignGalleryShowsSharedControls() {
        let app = launchSample(["CLOVE_DESIGN_GALLERY": "1"])
        XCTAssertTrue(element(app, "clove.design.gallery").exists)
        XCTAssertTrue(element(app, "clove.mark.toolbar").exists)
        XCTAssertTrue(element(app, "clove.mark.starBar").exists)
        let dark = element(app, "clove.design.gallery.mode.dark")
        dark.tap()
        XCTAssertTrue(dark.isSelected)
        let nord = element(app, "clove.design.gallery.family.nord")
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
            XCTAssertTrue(waitForLabel("MMQ02678.ARW", element(app, "clove.detail.fileName")))
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
                element(app, "clove.detail.filmstrip.group.burst-2678").tap()
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
            let rated = element(app, "clove.grid.group.burst-2678")
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
            XCTAssertTrue(element(app, "clove.detail.capsule").exists)
            capture("detail-zoom-\(theme)")
            preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4)).doubleTap()
            element(app, "clove.detail.capsule.reject").tap()
            XCTAssertTrue(waitForLabel("MMQ02682.ARW", element(app, "clove.detail.fileName")))
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
            element(app, "clove.settings.appearance.family.default").exists)
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
    func testDuoGridPhotoPreviewDockMarkAndFocusView() throws {
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
        let photoPreview = element(app, "clove.duo.photoPreview")
        XCTAssertTrue(photoPreview.waitForExistence(timeout: 5))
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertFalse(element(app, "clove.detail.rail").exists)
        XCTAssertFalse(element(app, "clove.detail.capsule").exists)
        XCTAssertFalse(element(app, "clove.detail.filmstrip").exists)
        let gridToggle = element(app, "clove.detail.gridToggle")
        XCTAssertTrue(gridToggle.exists)
        XCTAssertEqual(gridToggle.label, "Hide photo grid")
        XCTAssertEqual(gridToggle.value as? String, "Photo Preview")
        let grid = app.collectionViews.firstMatch
        XCTAssertEqual(
            grid.frame.width / (grid.frame.width + photoPreview.frame.width), 0.3, accuracy: 0.02)
        let focusToggles = app.buttons.matching(identifier: "clove.detail.focusToggle")
        XCTAssertEqual(focusToggles.count, 1)
        let focusToggle = element(app, "clove.detail.focusToggle")
        XCTAssertTrue(focusToggle.isHittable)
        XCTAssertEqual(focusToggle.value as? String, "On")
        XCTAssertGreaterThanOrEqual(focusToggle.frame.width, 43)
        XCTAssertGreaterThanOrEqual(focusToggle.frame.height, 43)
        XCTAssertGreaterThanOrEqual(focusToggle.frame.minX, grid.frame.maxX - 1)
        XCTAssertLessThanOrEqual(focusToggle.frame.maxY, preview.frame.minY + 1)
        XCTAssertLessThan(focusToggle.frame.maxX, element(app, "clove.detail.fileName").frame.minX)
        // #200: the marking capsule reserves its own row beneath the fitted photo, and
        // the side toolbar carries no duplicate marking items.
        let capsule = element(app, "clove.duo.capsule")
        XCTAssertTrue(capsule.exists)
        XCTAssertEqual(capsule.frame.width, 168, accuracy: 1)
        XCTAssertEqual(capsule.frame.height, 48, accuracy: 1)
        XCTAssertGreaterThanOrEqual(capsule.frame.minY, preview.frame.maxY)
        XCTAssertEqual(capsule.frame.maxX, photoPreview.frame.maxX - 16, accuracy: 1)
        XCTAssertFalse(element(app, "clove.duo.rating").exists)
        XCTAssertFalse(element(app, "clove.duo.reject").exists)
        XCTAssertFalse(element(app, "clove.duo.label").exists)
        capture("duo-photo-preview")
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
        // Off survives Photo Preview <-> Focus View and Focus View keeps a single header toggle.
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), focusToggle))
        // Native toggle switches Photo Preview <-> Focus View cleanly; then return to Photo Preview
        // to verify the divider drag still transitions as well.
        gridToggle.tap()
        let filmstrip = element(app, "clove.detail.filmstrip")
        XCTAssertTrue(filmstrip.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.duo.photoPreview").exists)
        XCTAssertEqual(gridToggle.label, "Show photo grid")
        XCTAssertEqual(gridToggle.value as? String, "Focus View")
        XCTAssertEqual(focusToggles.count, 1)
        XCTAssertEqual(focusToggle.value as? String, "Off")
        XCTAssertLessThanOrEqual(focusToggle.frame.maxY, preview.frame.minY + 1)
        XCTAssertLessThan(focusToggle.frame.maxX, element(app, "clove.detail.fileName").frame.minX)
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), focusToggle))
        gridToggle.tap()
        XCTAssertTrue(photoPreview.waitForExistence(timeout: 5))
        XCTAssertFalse(filmstrip.exists)
        let divider = element(app, "clove.duo.divider")
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.1,
            thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)))
        XCTAssertTrue(filmstrip.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.duo.photoPreview").exists)
        XCTAssertTrue(element(app, "clove.detail.fileName").exists)
        XCTAssertEqual(focusToggles.count, 1)
        XCTAssertLessThanOrEqual(focusToggle.frame.maxY, preview.frame.minY + 1)
        // In Focus View, the capsule stays beneath the photo and beside the narrowed filmstrip.
        XCTAssertGreaterThanOrEqual(capsule.frame.minY, preview.frame.maxY)
        XCTAssertGreaterThan(capsule.frame.midX, element(app, "clove.duo.focus").frame.midX)
        // View frames alone cannot see the interior dead space a content-side reservation leaves
        // (#237), so the content check below inspects where the strip's content actually rests.
        XCTAssertLessThanOrEqual(filmstrip.frame.maxX, capsule.frame.minX + 1)
        capture("duo-focus")
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
        capture("duo-focus-strip-end")
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
        XCTAssertFalse(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        stack.tap()
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5))
        element(app, "clove.detail.filmstrip.group.fold").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.filmstrip.expandedGroup")))
        let exit = swipeStripUntilHittable(
            "clove.detail.filmstrip.mmq02680", in: app, forward: true)
        exit.tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        let current = element(app, "clove.detail.filmstrip.mmq02680")
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), current),
            "the strip went blank after leaving the group")
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02680").waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.duo.capsule").exists)
    }

    /// #309: a group opened in expanded Duo scopes the split grid to that group, matching the
    /// Focus View filmstrip. Choosing a member keeps Group Focus; folding keeps the photo, its
    /// marks and the route, and the stack reopens it; Back returns to the full folder grid.
    @MainActor
    func testDuoExpandedGroupFocusScopesTheSplitGrid() throws {
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
        element(app, "clove.grid.group.burst-2696").tap()
        XCTAssertTrue(element(app, "clove.duo.photoPreview").waitForExistence(timeout: 5))
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", preview))
        // Group Focus draws only burst-2696's visible members: no neighbouring folder photos,
        // no other group and no collapsed stack of this group.
        let before = element(app, "clove.grid.photo.mmq02695")
        let after = element(app, "clove.grid.photo.mmq02699")
        XCTAssertFalse(before.exists, "A photo outside the group stayed in the split grid")
        XCTAssertFalse(after.exists, "A photo outside the group stayed in the split grid")
        XCTAssertFalse(element(app, "clove.grid.group.burst-2678").exists)
        XCTAssertFalse(element(app, "clove.grid.group.burst-2696").exists)
        let count = element(app, "clove.grid.group.count.burst-2696")
        XCTAssertTrue(count.exists, "The focused group has no header")
        XCTAssertEqual(count.label, "3 photos")
        let first = element(app, "clove.grid.photo.mmq02696")
        let third = element(app, "clove.grid.photo.mmq02698")
        XCTAssertTrue(first.isSelected)
        XCTAssertFalse(third.isSelected)
        capture("duo-group-focus-split-grid")
        // Folding changes the level only: the photo, its name and the route stay, and the full
        // folder comes back with the group's stack.
        element(app, "clove.grid.group.fold").tap()
        XCTAssertFalse(element(app, "clove.grid.group.count.burst-2696").exists)
        let stack = element(app, "clove.grid.group.burst-2696")
        XCTAssertTrue(stack.waitForExistence(timeout: 5), "Folding did not leave the group's stack")
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", preview))
        XCTAssertTrue(before.waitForExistence(timeout: 5))
        XCTAssertTrue(after.exists)
        XCTAssertTrue(element(app, "clove.grid.group.burst-2678").exists)
        capture("duo-group-focus-split-grid-folded")
        // The stack reopens the group without leaving the photo.
        stack.tap()
        XCTAssertTrue(
            element(app, "clove.grid.group.count.burst-2696").waitForExistence(timeout: 5))
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", preview))
        XCTAssertTrue(element(app, "clove.grid.photo.mmq02696").isSelected)
        XCTAssertFalse(before.exists)
        XCTAssertFalse(after.exists)
        // A member tap moves the preview, the filename and the marks, without leaving the group.
        third.tap()
        XCTAssertTrue(waitForLabel("MMQ02698.ARW", preview))
        XCTAssertTrue(third.isSelected)
        XCTAssertFalse(first.isSelected)
        XCTAssertTrue(count.exists)
        XCTAssertFalse(element(app, "clove.grid.photo.mmq02699").exists)
        let capsule = element(app, "clove.duo.capsule")
        rate(4, toolbar: "clove.duo.capsule", in: app)
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "4 stars"), capsule))
        XCTAssertTrue(third.label.contains("4 stars"))
        // Focus View keeps the same photo, the folder-order counter and the folder-order strip.
        let grid = app.collectionViews.firstMatch
        let divider = element(app, "clove.duo.divider")
        let start = divider.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        start.press(
            forDuration: 0.1,
            thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.02, dy: 0.5)))
        XCTAssertTrue(element(app, "clove.detail.filmstrip").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02698.ARW")
        XCTAssertTrue(
            element(app, "clove.detail.zoom").label.hasPrefix("Group · 3 / 3"),
            "The counter did not scope to the group: \(element(app, "clove.detail.zoom").label)")
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").exists,
            "The Focus View strip did not keep the expanded group")
        XCTAssertTrue(element(app, "clove.detail.filmstrip.mmq02696").exists)
        XCTAssertTrue(element(app, "clove.detail.filmstrip.mmq02698").exists)
        XCTAssertFalse(element(app, "clove.detail.filmstrip.mmq02695").exists)
        XCTAssertFalse(element(app, "clove.detail.filmstrip.mmq02699").exists)
        capture("duo-group-focus")
        // Folding the strip returns to Timeline on the representative photo; tapping its stack again
        // re-enters Group Focus.
        element(app, "clove.detail.filmstrip.group.fold").tap()
        XCTAssertFalse(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        let stripStack = element(app, "clove.detail.filmstrip.group.burst-2696")
        XCTAssertTrue(stripStack.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.filmstrip.mmq02695").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02698.ARW")
        capture("duo-group-focus-folded")
        stripStack.tap()
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02698.ARW")
        XCTAssertFalse(element(app, "clove.detail.filmstrip.mmq02695").exists)
        // Back returns to the full collapsed folder grid with its filter and browsing position.
        element(app, "clove.nav.back").tap()
        XCTAssertTrue(element(app, "clove.grid.more").waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.grid.title").label, "Coastal light")
        XCTAssertTrue(element(app, "clove.grid.group.burst-2696").exists)
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
        XCTAssertFalse(element(app, "clove.detail.gridToggle").exists)
        XCTAssertFalse(element(app, "clove.detail.photoGrid").exists)
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
        let focusIndicators = element(app, "clove.detail.focusIndicators")
        let faceIndicator = element(app, "clove.detail.focusIndicator.face")
        let missingAFIndicator = element(app, "clove.detail.focusIndicator.autofocus")
        XCTAssertTrue(focusToggle.waitForExistence(timeout: 5))
        XCTAssertEqual(app.buttons.matching(identifier: "clove.detail.focusToggle").count, 1)
        XCTAssertEqual(focusToggle.value as? String, "On")
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
        XCTAssertTrue(separatedEye.exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.1-0").exists)
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "Face detected")
        XCTAssertFalse(missingAFIndicator.exists)
        capture("duo-cover-focus-on")
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), focusToggle))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), overlapAF))
        XCTAssertFalse(separatedEye.exists)
        XCTAssertFalse(focusIndicators.exists)
        capture("duo-cover-focus-off")
        element(app, "clove.detail.preview").swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02684.ARW", element(app, "clove.detail.fileName")))
        XCTAssertEqual(focusToggle.value as? String, "Off")
        XCTAssertFalse(overlapAF.exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertFalse(focusIndicators.exists)
        focusToggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), focusToggle))
        XCTAssertTrue(overlapAF.waitForExistence(timeout: 5))
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "Face detected")
        XCTAssertFalse(missingAFIndicator.exists)
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

        // Folding Group Focus swaps the strip's isolated member row back to the Timeline strip, so
        // this verifies the strip stays populated across both transition directions.
        element(app, "clove.grid.group.burst-2678").tap()
        XCTAssertTrue(waitForLabel("MMQ02678.ARW", fileName))
        XCTAssertTrue(strip.waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        // #305: the dock keeps its height as the pill comes and goes, so the stage never resizes.
        // Every member starts unmarked, so Group Focus offers no pill; folding to Timeline on the
        // collapsed stack offers "Expand N photos" above the dock.
        let duoPreview = element(app, "clove.detail.preview")
        let stageWithoutPill = duoPreview.frame
        XCTAssertFalse(element(app, "clove.detail.rejectUnmarked").exists)
        element(app, "clove.detail.filmstrip.group.fold").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.filmstrip.expandedGroup")))
        let expandPill = element(app, "clove.detail.expandGroup")
        XCTAssertTrue(expandPill.waitForExistence(timeout: 5))
        assertSameFrame(
            duoPreview.frame, stageWithoutPill, "the pill resized the Duo cover stage")
        XCTAssertTrue(expandPill.isHittable)
        element(app, "clove.detail.filmstrip.mmq02680").tap()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        XCTAssertTrue(element(app, "clove.detail.filmstrip.group.burst-2678").exists)
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), expandPill))
        assertSameFrame(
            duoPreview.frame, stageWithoutPill, "the pill leaving resized the Duo cover stage")
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

        // Entering a group from its stack, a within-group move, and folding back to Timeline cover
        // the two-level filmstrip transitions and off-screen destinations (#237, #304).
        let stack = swipeStripUntilHittable(
            "clove.detail.filmstrip.group.burst-2696", in: app, forward: false)
        stack.tap()
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", fileName))
        XCTAssertFalse(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        stack.tap()
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5),
            "the strip stayed blank after entering the group")
        let member = swipeStripUntilHittable(
            "clove.detail.filmstrip.mmq02698", in: app, forward: true)
        member.tap()
        XCTAssertTrue(waitForLabel("MMQ02698.ARW", fileName))
        element(app, "clove.detail.filmstrip.group.fold").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.filmstrip.expandedGroup")))
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
    /// (#272). The expanded Photo Preview split (`clove.duo.photoPreview`) cannot enter Open pose
    /// headlessly and is verified on TestFlight.
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

        element(app, "clove.grid.group.burst-2678").tap()
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
        XCTAssertTrue(neighborCurrent.isSelected)
        XCTAssertFalse(neighborLeft.isSelected)
        XCTAssertFalse(stack.isSelected)

        // First tap on a collapsed stack opens its representative in Timeline without expanding;
        // neighbors stay anchored in place and the Expand nudge appears.
        stack.tap()
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", fileName))
        XCTAssertFalse(element(app, "clove.detail.filmstrip.expandedGroup").exists)
        XCTAssertTrue(element(app, "clove.detail.expandGroup").waitForExistence(timeout: 5))
        XCTAssertEqual(neighborLeft.frame.minX, leftBefore.minX, accuracy: 2)
        XCTAssertEqual(neighborCurrent.frame.minX, currentBefore.minX, accuracy: 2)
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == true"), stack))
        XCTAssertFalse(neighborCurrent.isSelected)

        // Second tap on the selected group's stack enters isolated Group Focus.
        stack.tap()
        XCTAssertTrue(
            element(app, "clove.detail.filmstrip.expandedGroup").waitForExistence(timeout: 5))
        let firstMember = element(app, "clove.detail.filmstrip.mmq02696")
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), firstMember))
        XCTAssertTrue(firstMember.isSelected)
        XCTAssertFalse(neighborCurrent.exists)

        // Tapping another visible member keeps firstMember anchored in Group Focus.
        let firstMemberBeforeTap = firstMember.frame
        let secondMember = element(app, "clove.detail.filmstrip.mmq02697")
        XCTAssertTrue(secondMember.isHittable)
        secondMember.tap()
        XCTAssertTrue(waitForLabel("MMQ02697.ARW", fileName))
        XCTAssertEqual(firstMember.frame.minX, firstMemberBeforeTap.minX, accuracy: 2)
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == true"), secondMember))
        XCTAssertFalse(firstMember.isSelected)

        // Folding returns to Timeline on the Representative Photo (MMQ02696), centering the stack;
        // tapping a visible neighbor keeps Timeline items anchored in place without jumping.
        element(app, "clove.detail.filmstrip.group.fold").tap()
        XCTAssertTrue(
            wait(
                NSPredicate(format: "exists == false"),
                element(app, "clove.detail.filmstrip.expandedGroup")))
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", fileName))
        XCTAssertTrue(stack.waitForExistence(timeout: 5))
        XCTAssertTrue(stack.isSelected)
        XCTAssertTrue(neighborCurrent.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), neighborCurrent))
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), neighborLeft))
        let leftAfterCollapse = neighborLeft.frame
        let currentAfterCollapse = neighborCurrent.frame
        let stackAfterCollapse = stack.frame
        neighborCurrent.tap()
        XCTAssertTrue(waitForLabel("MMQ02695.ARW", fileName))
        XCTAssertEqual(neighborLeft.frame.minX, leftAfterCollapse.minX, accuracy: 2)
        XCTAssertEqual(neighborCurrent.frame.minX, currentAfterCollapse.minX, accuracy: 2)
        XCTAssertEqual(stack.frame.minX, stackAfterCollapse.minX, accuracy: 2)
        XCTAssertTrue(wait(NSPredicate(format: "isSelected == true"), neighborCurrent))
        XCTAssertFalse(stack.isSelected)

        // Navigating forward across collapsed burst-2696 to an off-screen photo brings it into view (#252, #255).
        let preview = element(app, "clove.detail.preview")
        for _ in 0..<6 {
            preview.swipeLeft()
        }
        XCTAssertTrue(waitForLabel("MMQ02703.ARW", fileName))
        let offscreenTarget = element(app, "clove.detail.filmstrip.mmq02703")
        XCTAssertTrue(
            wait(NSPredicate(format: "isHittable == true"), offscreenTarget),
            "off-screen navigation did not bring the destination thumbnail into view")
    }

    @MainActor
    func testGroupFocusUpSwipeOverMemberCollapsesAndAllowsImmediateTimelineFlick() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_GROUP_STATE": "unmarked"])
        defer { app.terminate() }
        openLibrary(app)

        element(app, "clove.grid.photo.mmq02695").tap()
        let fileName = element(app, "clove.detail.fileName")
        XCTAssertTrue(waitForLabel("MMQ02695.ARW", fileName))

        let stack = element(app, "clove.detail.filmstrip.group.burst-2696")
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), stack))
        stack.tap()
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", fileName))

        // Downward vertical swipe on the collapsed stack enters Group Focus.
        let stackCenter = stack.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        stackCenter.press(
            forDuration: 0.05,
            thenDragTo: stackCenter.withOffset(CGVector(dx: 0, dy: 70)))
        let expandedTray = element(app, "clove.detail.filmstrip.expandedGroup")
        XCTAssertTrue(expandedTray.waitForExistence(timeout: 5))

        let fold = element(app, "clove.detail.filmstrip.group.fold")
        let firstMember = element(app, "clove.detail.filmstrip.mmq02696")
        let secondMember = element(app, "clove.detail.filmstrip.mmq02697")
        let thirdMember = element(app, "clove.detail.filmstrip.mmq02698")
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), fold))
        XCTAssertTrue(wait(NSPredicate(format: "isHittable == true"), thirdMember))
        XCTAssertGreaterThanOrEqual(fold.frame.minX, thirdMember.frame.maxX - 1)
        XCTAssertLessThan(fold.frame.maxX - firstMember.frame.minX, 230)

        secondMember.tap()
        XCTAssertTrue(waitForLabel("MMQ02697.ARW", fileName))

        // Upward vertical swipe directly over a non-first member collapses to Timeline on the
        // Representative Photo without firing the underlying member tap action.
        let thirdCenter = thirdMember.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        thirdCenter.press(
            forDuration: 0.05,
            thenDragTo: thirdCenter.withOffset(CGVector(dx: 0, dy: -80)))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), expandedTray))
        XCTAssertTrue(waitForLabel("MMQ02696.ARW", fileName))
        XCTAssertTrue(element(app, "clove.detail.expandGroup").waitForExistence(timeout: 5))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "isHittable == true"),
                element(app, "clove.detail.filmstrip.mmq02695")))

        // Immediately flicking left on the stage advances cleanly across Timeline slots.
        element(app, "clove.detail.preview").swipeLeft(velocity: .fast)
        XCTAssertTrue(waitForLabel("MMQ02699.ARW", fileName))
    }

    @MainActor
    func testDetailFocusRegionsCentreNativeZoom() throws {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        turnOffAutoAdvance(app)
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.group.burst-2678").tap()
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let toggle = element(app, "clove.detail.focusToggle")
        let autofocus = element(app, "clove.detail.region.af.0")
        let eye = element(app, "clove.detail.region.face.1-0")
        let focusIndicators = element(app, "clove.detail.focusIndicators")
        let faceIndicator = element(app, "clove.detail.focusIndicator.face")
        let missingAFIndicator = element(app, "clove.detail.focusIndicator.autofocus")
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        XCTAssertEqual(toggle.value as? String, "On")
        XCTAssertTrue(autofocus.waitForExistence(timeout: 5))
        XCTAssertTrue(eye.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.2-0").exists)
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "Face detected")
        XCTAssertFalse(missingAFIndicator.exists)
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

        // Double-tapping away from the AF rectangle (including near the edges, #252) still
        // centres 100% on AF; a second double-tap anywhere returns to fit.
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
            thenDragTo: eyeSwipe.withOffset(CGVector(dx: 0, dy: 55)),
            withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertEqual(element(app, "clove.detail.fileName").label, fileName)
        let eyeMarkValue = element(app, "clove.detail.capsule").value as? String
        XCTAssertEqual(
            eyeMarkValue, "Red",
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
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "No faces detected")
        XCTAssertFalse(missingAFIndicator.exists)
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
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "Face detected")
        XCTAssertFalse(missingAFIndicator.exists)
        capture("detail-focus-regions-overlap-light")

        toggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Off"), toggle))
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), overlapAF))
        XCTAssertFalse(personOneEye.exists)
        XCTAssertFalse(focusIndicators.exists)
        capture("detail-focus-regions-off-light")

        // Navigating while Off keeps regions and indicators suppressed.
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02684.ARW", element(app, "clove.detail.fileName")))
        XCTAssertEqual(toggle.value as? String, "Off")
        XCTAssertFalse(element(app, "clove.detail.region.af.0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertFalse(focusIndicators.exists)

        // Turning On reveals AF + face fallback (four corner brackets) on MMQ02684.
        toggle.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "On"), toggle))
        XCTAssertTrue(element(app, "clove.detail.region.af.0").waitForExistence(timeout: 5))
        XCTAssertTrue(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "Face detected")
        XCTAssertFalse(missingAFIndicator.exists)
        capture("detail-focus-regions-face-fallback-light")

        // Photo with no focus regions keeps tap-point double-tap zoom anywhere, shows missing-AF +
        // no-faces indicators, passes upper-leading corner taps through, and hides with chrome.
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.photo.mmq02680").tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertFalse(element(app, "clove.detail.region.af.0").exists)
        XCTAssertFalse(element(app, "clove.detail.region.face.0-0").exists)
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(faceIndicator.label, "No faces detected")
        XCTAssertTrue(missingAFIndicator.waitForExistence(timeout: 5))
        XCTAssertEqual(missingAFIndicator.label, "No autofocus metadata")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.5)).doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "label ENDSWITH %@", "100%"), zoom))
        XCTAssertTrue(
            wait(
                NSPredicate(format: "value CONTAINS %@", "centred at 65%, 50%"), preview),
            "Double-tap on a photo with no focus regions should centre on the tap point")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.06, dy: 0.5)).doubleTap()
        XCTAssertFalse(zoom.label.hasSuffix("100%"))
        XCTAssertEqual(element(app, "clove.detail.fileName").label, "MMQ02680.ARW")
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.08)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), focusIndicators))
        preview.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.08)).tap()
        XCTAssertTrue(faceIndicator.waitForExistence(timeout: 5))
        XCTAssertTrue(missingAFIndicator.exists)
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

        // 2. Select all before selection, mixed batch labels/Clear rating, and outside-tap dismiss.
        element(app, "clove.grid.more").tap()
        app.buttons["Select"].tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "0 selected")
        element(app, "clove.grid.selectionOptions").tap()
        app.buttons["Select all"].tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "36 selected")
        XCTAssertTrue(element(app, "clove.grid.batch.rating").isEnabled)
        element(app, "clove.grid.batch.done").tap()

        // Pair unrated mmq02684 with standalone 2-star Purple mmq02699 (collapsed group covers omit
        // member marks from their accessibility label).
        let unmarked = element(app, "clove.grid.photo.mmq02684")
        XCTAssertTrue(unmarked.waitForExistence(timeout: 5))
        unmarked.press(forDuration: 0.6)
        let batchBar = element(app, "clove.grid.batch")
        XCTAssertTrue(batchBar.waitForExistence(timeout: 5))
        let rated = element(app, "clove.grid.photo.mmq02699")
        let gridCollection = element(app, "clove.grid").collectionViews.firstMatch
        for _ in 0..<6 {
            if rated.exists && rated.isHittable && rated.frame.maxY < batchBar.frame.minY - 8 {
                break
            }
            gridCollection.swipeUp()
        }
        XCTAssertTrue(rated.waitForExistence(timeout: 5))
        rated.tap()
        XCTAssertEqual(element(app, "clove.grid.batch.count").label, "2 selected")

        element(app, "clove.grid.batch.label").tap()
        let batchPicker = element(app, "clove.grid.batch.labels")
        XCTAssertTrue(batchPicker.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.grid.batch.labels.none").isSelected)
        XCTAssertFalse(element(app, "clove.grid.batch.labels.purple").isSelected)
        element(app, "clove.grid").coordinate(withNormalizedOffset: CGVector(dx: 0.65, dy: 0.3))
            .tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), batchPicker))

        batchBar.press(forDuration: 0.6)
        app.buttons["Clear rating"].tap()
        XCTAssertTrue(wait(NSPredicate(format: "NOT (label CONTAINS %@)", "stars"), rated))
        XCTAssertTrue(rated.label.contains("Purple"))

        element(app, "clove.grid.batch.label").tap()
        XCTAssertTrue(batchPicker.waitForExistence(timeout: 5))
        element(app, "clove.grid.batch.labels.none").tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), batchPicker))
        XCTAssertTrue(wait(NSPredicate(format: "NOT (label CONTAINS %@)", "Purple"), rated))
        element(app, "clove.grid.batch.done").tap()

        rated.tap()
        let rail = element(app, "clove.detail.rail")
        let marksControl = rail.exists ? rail : element(app, "clove.detail.capsule")
        XCTAssertTrue(marksControl.waitForExistence(timeout: 5))
        XCTAssertEqual(marksControl.value as? String, "Unmarked")
    }

    /// #302: the default zoomed mode keeps one-finger rating and photo switching, `Pan` keeps the
    /// one-finger pan with a two-finger rating swipe, and the chrome stays steady at both scales.
    @MainActor
    func testZoomedRatingSwipeModesAndPinchSafety() throws {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)

        element(app, "clove.grid.photo.mmq02680").tap()
        let preview = element(app, "clove.detail.preview")
        let fileName = element(app, "clove.detail.fileName")
        let capsule = element(app, "clove.detail.capsule")
        let zoom = element(app, "clove.detail.zoom")
        let strip = element(app, "clove.detail.filmstrip")
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        XCTAssertEqual(capsule.value as? String, "Unmarked")

        // Fit gestures remain unchanged in the default mode.
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))

        // Pinching zooms and never rates, and every togglable chrome item stays where it was.
        preview.pinch(withScale: 2.0, velocity: 1.0)
        XCTAssertEqual(fileName.label, "MMQ02680.ARW")
        XCTAssertEqual(capsule.value as? String, "Unmarked")
        XCTAssertTrue(strip.exists)
        XCTAssertTrue(element(app, "clove.detail.info").exists)
        let centre = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.4))
        centre.doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        centre.doubleTap()
        XCTAssertEqual(zoom.label, "2 / 32 · 100%")
        XCTAssertEqual(capsule.value as? String, "Unmarked")
        XCTAssertTrue(strip.exists)

        // A one-finger horizontal drag while zoomed switches photo instead of panning the image,
        // and the photo outside the group opens at fit.
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))

        // A one-finger vertical drag while zoomed rates, auto-advances, and returns to fit.
        centre.doubleTap()
        XCTAssertEqual(zoom.label, "2 / 32 · 100%")
        let verticalStart = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.65))
        verticalStart.press(
            forDuration: 0.02, thenDragTo: verticalStart.withOffset(CGVector(dx: 0, dy: -180)),
            withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName, timeout: 10))
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        XCTAssertFalse(element(app, "clove.detail.swipeFeedback").exists)
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02680.ARW", fileName))
        XCTAssertTrue((capsule.value as? String)?.contains("stars") == true)

        // Switch the zoomed mode to Pan.
        element(app, "clove.nav.back").tap()
        element(app, "clove.grid.more").tap()
        app.buttons["Settings"].tap()
        openSettingsCategory("clove.settings.category.culling", in: app)
        let zoomedGesturesSetting = element(app, "clove.settings.zoomedGestures")
        for _ in 0..<8 {
            if zoomedGesturesSetting.exists && zoomedGesturesSetting.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(zoomedGesturesSetting.isHittable)
        zoomedGesturesSetting.tap()
        app.buttons["Pan"].tap()
        XCTAssertTrue(
            String(describing: zoomedGesturesSetting.value).contains("Pan")
                || zoomedGesturesSetting.label.contains("Pan"))
        element(app, "clove.nav.back").tap()

        // Open standalone unrated photo MMQ02682.ARW in Pan mode.
        let standalone = element(app, "clove.grid.photo.mmq02682")
        XCTAssertTrue(standalone.waitForExistence(timeout: 5))
        standalone.tap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))
        let panModeMarks = capsule.value as? String
        XCTAssertEqual(panModeMarks, "Green")

        // Fit horizontal navigation still works with the Pan mode active.
        preview.swipeLeft()
        XCTAssertTrue(waitForLabel("MMQ02683.ARW", fileName))
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))

        // Pinching still zooms and never rates.
        preview.pinch(withScale: 2.0, velocity: 1.0)
        XCTAssertEqual(fileName.label, "MMQ02682.ARW")
        XCTAssertEqual(capsule.value as? String, panModeMarks)
        centre.doubleTap()
        XCTAssertTrue(wait(NSPredicate(format: "value == %@", "Loaded"), preview))

        // Zoom to 100%: one-finger drags pan the image without navigating or rating, and a
        // two-finger vertical swipe rates + auto-advances + returns to fit.
        centre.doubleTap()
        XCTAssertEqual(zoom.label, "3 / 32 · 100%")
        let centredBeforePan = preview.value as? String
        let panStart = preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        panStart.press(
            forDuration: 0.05, thenDragTo: panStart.withOffset(CGVector(dx: 0, dy: -150)),
            withVelocity: .slow, thenHoldForDuration: 0)
        XCTAssertEqual(fileName.label, "MMQ02682.ARW")
        XCTAssertEqual(zoom.label, "3 / 32 · 100%")
        XCTAssertEqual(capsule.value as? String, panModeMarks)
        XCTAssertNotEqual(preview.value as? String, centredBeforePan)

        try swipeTwoFingersVertically(in: preview, deltaY: -180, app: app)
        XCTAssertTrue(waitForLabel("MMQ02683.ARW", fileName, timeout: 10))
        XCTAssertTrue(wait(NSPredicate(format: "exists == true"), capsule))
        XCTAssertFalse(element(app, "clove.detail.swipeFeedback").exists)
        preview.swipeRight()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
        XCTAssertTrue((capsule.value as? String)?.contains("stars") == true)
    }

    @MainActor
    func testOverlappingZoomPanTwoFingerSwipeAndPinchRemainResponsive() throws {
        let app = launchSample()
        defer { app.terminate() }
        openLibrary(app)

        let stack = element(app, "clove.grid.group.burst-2678")
        if stack.exists {
            stack.tap()
        } else {
            element(app, "clove.grid.photo.mmq02678").tap()
        }
        let preview = element(app, "clove.detail.preview")
        XCTAssertTrue(wait(NSPredicate(format: "value CONTAINS %@", "Loaded"), preview))
        let frame = preview.frame

        for round in 0..<4 {
            try synthesizeOverlappingZoomPanSwipe(
                in: frame,
                swipeDeltaY: round.isMultiple(of: 2) ? -160 : 160,
                includePostSwipePinch: round >= 2,
                includeChromeTap: round.isMultiple(of: 2))
            XCTAssertTrue(preview.waitForExistence(timeout: 5), "App wedged in round \(round)")
            if (preview.value as? String)?.contains("centred at") == true {
                preview.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).doubleTap()
            }
        }
        XCTAssertTrue(preview.waitForExistence(timeout: 5))
    }

    @MainActor
    private func synthesizeOverlappingZoomPanSwipe(
        in frame: CGRect,
        swipeDeltaY: CGFloat,
        includePostSwipePinch: Bool,
        includeChromeTap: Bool
    ) throws {
        guard
            let pathClass = NSClassFromString("XCPointerEventPath") as? NSObject.Type,
            let recordClass = NSClassFromString("XCSynthesizedEventRecord") as? NSObject.Type
        else { return }
        let allocSel = NSSelectorFromString("alloc")
        let initTouchSel = NSSelectorFromString("initForTouchAtPoint:offset:")
        let moveSel = NSSelectorFromString("moveToPoint:atOffset:")
        let liftSel = NSSelectorFromString("liftUpAtOffset:")
        let initRecordSel = NSSelectorFromString("initWithName:interfaceOrientation:")
        let addPathSel = NSSelectorFromString("addPointerEventPath:")
        let synthesizeErrorSel = NSSelectorFromString("synthesizeWithError:")

        typealias AllocIMP = @convention(c) (AnyClass, Selector) -> AnyObject
        typealias InitTouchIMP =
            @convention(c) (AnyObject, Selector, CGPoint, TimeInterval) -> AnyObject
        typealias MoveIMP = @convention(c) (AnyObject, Selector, CGPoint, TimeInterval) -> Void
        typealias LiftIMP = @convention(c) (AnyObject, Selector, TimeInterval) -> Void
        typealias InitRecordIMP =
            @convention(c) (AnyObject, Selector, NSString, Int) -> AnyObject
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
        let synthesize = unsafeBitCast(
            class_getMethodImplementation(recordClass, synthesizeErrorSel),
            to: SynthesizeErrorIMP.self)

        let mid = CGPoint(x: frame.midX, y: frame.midY)
        let record = initRecord(
            allocRecord(recordClass, allocSel), initRecordSel, "ZoomPanTwoFinger" as NSString, 1)

        // Tap 1 + Tap 2 (double tap to 100%)
        let tap1 = initTouch(allocPath(pathClass, allocSel), initTouchSel, mid, 0.0)
        liftUp(tap1, liftSel, 0.03)
        let tap2 = initTouch(allocPath(pathClass, allocSel), initTouchSel, mid, 0.08)
        liftUp(tap2, liftSel, 0.11)
        addPath(record, addPathSel, tap1)
        addPath(record, addPathSel, tap2)

        // Pan immediately at t=0.22..0.38 (fast enough to leave UIScrollView decelerating)
        let panStart = CGPoint(x: frame.midX + 40, y: frame.midY + 40)
        let pan = initTouch(allocPath(pathClass, allocSel), initTouchSel, panStart, 0.22)
        for step in 1...6 {
            let f = CGFloat(step) / 6.0
            let point = CGPoint(x: panStart.x - 110 * f, y: panStart.y - 75 * f)
            moveTo(pan, moveSel, point, 0.22 + 0.025 * Double(step))
        }
        liftUp(pan, liftSel, 0.38)
        addPath(record, addPathSel, pan)

        // Two-finger vertical swipe immediately at t=0.41 while decelerating
        let startY = frame.midY + (swipeDeltaY < 0 ? 70 : -70)
        let leftStart = CGPoint(x: frame.midX - 35, y: startY)
        let rightStart = CGPoint(x: frame.midX + 35, y: startY)
        let left = initTouch(allocPath(pathClass, allocSel), initTouchSel, leftStart, 0.41)
        let right = initTouch(allocPath(pathClass, allocSel), initTouchSel, rightStart, 0.41)
        for step in 1...8 {
            let f = CGFloat(step) / 8.0
            let t = 0.43 + 0.025 * Double(step)
            moveTo(left, moveSel, CGPoint(x: leftStart.x, y: leftStart.y + swipeDeltaY * f), t)
            moveTo(right, moveSel, CGPoint(x: rightStart.x, y: rightStart.y + swipeDeltaY * f), t)
        }
        liftUp(left, liftSel, 0.65)
        liftUp(right, liftSel, 0.66)
        addPath(record, addPathSel, left)
        addPath(record, addPathSel, right)

        // Collide a pan or pinch right around the 0.3s auto-advance window (t=0.90..1.10)
        if includePostSwipePinch {
            let p1Start = CGPoint(x: frame.midX - 30, y: frame.midY)
            let p2Start = CGPoint(x: frame.midX + 30, y: frame.midY)
            let p1 = initTouch(allocPath(pathClass, allocSel), initTouchSel, p1Start, 0.90)
            let p2 = initTouch(allocPath(pathClass, allocSel), initTouchSel, p2Start, 0.90)
            for step in 1...6 {
                let f = CGFloat(step) / 6.0
                let t = 0.92 + 0.025 * Double(step)
                moveTo(p1, moveSel, CGPoint(x: p1Start.x - 50 * f, y: p1Start.y), t)
                moveTo(p2, moveSel, CGPoint(x: p2Start.x + 50 * f, y: p2Start.y), t)
            }
            liftUp(p1, liftSel, 1.10)
            liftUp(p2, liftSel, 1.10)
            addPath(record, addPathSel, p1)
            addPath(record, addPathSel, p2)
        } else {
            let collidePan = initTouch(allocPath(pathClass, allocSel), initTouchSel, mid, 0.92)
            for step in 1...5 {
                let f = CGFloat(step) / 5.0
                let point = CGPoint(x: mid.x + 80 * f, y: mid.y + 60 * f)
                moveTo(collidePan, moveSel, point, 0.92 + 0.03 * Double(step))
            }
            liftUp(collidePan, liftSel, 1.10)
            addPath(record, addPathSel, collidePan)
        }
        if includeChromeTap {
            let chromePoint = CGPoint(x: frame.midX + 50, y: frame.midY - 50)
            let chromeTap = initTouch(
                allocPath(pathClass, allocSel), initTouchSel, chromePoint, 0.16)
            liftUp(chromeTap, liftSel, 0.19)
            addPath(record, addPathSel, chromeTap)
        }

        var error: NSError?
        XCTAssertTrue(
            synthesize(record, synthesizeErrorSel, &error), "\(String(describing: error))")
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
    func testFolderPreparationInlineIndicatorAndDetailsPresentation() {
        let app = launchSample(["CLOVE_TEST_LIBRARY_PREPARATION": "preparing"])
        defer { app.terminate() }
        openLibrary(app)

        let gridPrep = element(app, "clove.grid.preparation")
        XCTAssertTrue(gridPrep.waitForExistence(timeout: 5))
        XCTAssertTrue(gridPrep.isHittable)
        XCTAssertEqual(gridPrep.label, "Folder preparation")
        XCTAssertEqual(gridPrep.value as? String, "15 of 36 ready")
        XCTAssertGreaterThanOrEqual(gridPrep.frame.width, 43)
        XCTAssertGreaterThanOrEqual(gridPrep.frame.height, 43)

        if UIDevice.current.userInterfaceIdiom == .phone {
            let gridTitle = element(app, "clove.grid.title")
            XCTAssertTrue(gridTitle.exists)
            XCTAssertGreaterThanOrEqual(gridPrep.frame.midX, gridTitle.frame.maxX - 4)
        }

        gridPrep.tap()
        let details = element(app, "clove.preparation.details")
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.preparation.folderName").label, "Coastal light")
        XCTAssertEqual(element(app, "clove.preparation.summary").label, "15 of 36 ready")
        XCTAssertEqual(element(app, "clove.preparation.analysis.count").label, "18 of 36 analyzed")
        XCTAssertEqual(element(app, "clove.preparation.previews.count").label, "29 of 36 prepared")
        XCTAssertTrue(
            element(app, "clove.preparation.analysis.progress").waitForExistence(timeout: 5))
        XCTAssertTrue(
            element(app, "clove.preparation.previews.progress").waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Pause"].exists)
        XCTAssertFalse(app.buttons["Cancel"].exists)

        let doneButton = element(app, "clove.preparation.done")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertFalse(doneButton.exists)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85)).tap()
        } else {
            XCTAssertTrue(doneButton.exists)
            doneButton.tap()
        }
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), details))

        // Open Detail and verify inline ring beside filename without colliding with #292's focus toggle.
        element(app, "clove.grid.photo.mmq02680").tap()
        let fileName = element(app, "clove.detail.fileName")
        XCTAssertTrue(fileName.waitForExistence(timeout: 5))
        let detailPrep = element(app, "clove.detail.preparation")
        XCTAssertTrue(detailPrep.waitForExistence(timeout: 5))
        XCTAssertTrue(detailPrep.isHittable)
        XCTAssertEqual(detailPrep.value as? String, "15 of 36 ready")
        XCTAssertGreaterThanOrEqual(detailPrep.frame.width, 43)
        XCTAssertGreaterThanOrEqual(detailPrep.frame.height, 43)

        let focusToggle = element(app, "clove.detail.focusToggle")
        XCTAssertTrue(focusToggle.exists)
        XCTAssertLessThan(focusToggle.frame.maxX, detailPrep.frame.minX)
        XCTAssertFalse(focusToggle.frame.intersects(detailPrep.frame))
        XCTAssertGreaterThanOrEqual(detailPrep.frame.midX, fileName.frame.maxX - 4)
        XCTAssertTrue(element(app, "clove.detail.zoom").exists)

        let info = element(app, "clove.detail.info")
        if info.exists {
            XCTAssertLessThanOrEqual(detailPrep.frame.maxX, info.frame.minX + 16)
        }

        detailPrep.tap()
        XCTAssertTrue(details.waitForExistence(timeout: 5))
        XCTAssertEqual(element(app, "clove.preparation.summary").label, "15 of 36 ready")
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCTAssertFalse(doneButton.exists)
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.85)).tap()
        } else {
            doneButton.tap()
        }
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), details))

        // Culling remains active and responsive with preparation ring shown.
        let rejectButton = element(
            app,
            UIDevice.current.userInterfaceIdiom == .pad
                ? "clove.detail.rail.reject" : "clove.detail.capsule.reject")
        rejectButton.tap()
        XCTAssertTrue(waitForLabel("MMQ02682.ARW", fileName))
    }

    @MainActor
    func testCaptureTapPickerReferencesWhenRequested() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["CLOVE_CAPTURE_TAP_PICKERS"] == "1")
        defer { XCUIDevice.shared.orientation = .portrait }

        // 1. Design gallery across Light, Dark, and Nord (values 0–5, rejected, disabled, mixed, vertical, all labels).
        let gallery = launchSample(["CLOVE_DESIGN_GALLERY": "1"])
        for (mode, family, theme) in [
            ("light", "default", "light"),
            ("dark", "default", "dark"),
            ("dark", "nord", "nord"),
        ] {
            element(gallery, "clove.design.gallery.mode.\(mode)").tap()
            element(gallery, "clove.design.gallery.family.\(family)").tap()
            let scroll = gallery.scrollViews.firstMatch
            let ratingAnchor = element(gallery, "clove.mark.ratingPicker")
            for _ in 0..<4 where !ratingAnchor.isHittable { scroll.swipeUp() }
            capture("gallery-tap-pickers-rating-\(theme)")
            let labelAnchor = element(gallery, "clove.design.gallery.labelPicker.vertical")
            for _ in 0..<4 where !labelAnchor.isHittable { scroll.swipeUp() }
            capture("gallery-tap-pickers-label-\(theme)")
            for _ in 0..<6
            where !element(gallery, "clove.design.gallery.family.\(family)").isHittable {
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
                let rated = element(app, "clove.grid.group.burst-2678")
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
    func testPhoneLandscapeGridAndDetailWorkflow() throws {
        guard UIDevice.current.userInterfaceIdiom == .phone else {
            throw XCTSkip("Dedicated iPhone landscape workflow")
        }
        let app = launchSample()
        defer {
            app.terminate()
            XCUIDevice.shared.orientation = .portrait
        }
        XCUIDevice.shared.orientation = .portrait
        openLibrary(app)

        // Portrait -> landscapeLeft in Grid: full safe-area grid, no iPad rail or sidebar toggle.
        XCUIDevice.shared.orientation = .landscapeLeft
        let grid = element(app, "clove.grid")
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        XCTAssertTrue(wait(NSPredicate { _, _ in grid.frame.width > grid.frame.height }, grid))
        XCTAssertFalse(element(app, "clove.detail.gridToggle").exists)

        // Tapping a group stack opens single-photo Group Focus (never Photo Preview) with the
        // dedicated bottom review row and compact inline header pill.
        let groupTile = element(app, "clove.grid.group.burst-2678")
        XCTAssertTrue(groupTile.waitForExistence(timeout: 5))
        groupTile.tap()

        let bottomRow = element(app, "clove.detail.landscapeBottomRow")
        let filmstrip = element(app, "clove.detail.filmstrip")
        let capsule = element(app, "clove.detail.capsule")
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 5))
        XCTAssertTrue(filmstrip.waitForExistence(timeout: 5))
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        XCTAssertFalse(element(app, "clove.detail.gridToggle").exists)
        XCTAssertFalse(element(app, "clove.detail.photoGrid").exists)
        XCTAssertFalse(element(app, "clove.detail.rail").exists)
        XCTAssertLessThanOrEqual(filmstrip.frame.maxX, capsule.frame.minX + 1)

        // Header controls & Group Focus pill coexist without overlapping inside the header.
        let back = element(app, "clove.nav.back")
        let focus = element(app, "clove.detail.focusToggle")
        let fileName = element(app, "clove.detail.fileName")
        let rejectPill = element(app, "clove.detail.rejectUnmarked")
        let info = element(app, "clove.detail.info")
        let undo = element(app, "clove.detail.undo")
        XCTAssertTrue(back.exists)
        XCTAssertTrue(focus.exists)
        XCTAssertTrue(fileName.exists)
        XCTAssertTrue(rejectPill.waitForExistence(timeout: 5))
        XCTAssertTrue(info.exists)
        XCTAssertTrue(undo.exists)
        XCTAssertLessThanOrEqual(back.frame.maxX, focus.frame.minX + 1)
        XCTAssertLessThanOrEqual(focus.frame.maxX, fileName.frame.minX + 1)
        XCTAssertLessThanOrEqual(fileName.frame.maxX, rejectPill.frame.minX + 1)
        XCTAssertLessThanOrEqual(rejectPill.frame.maxX, info.frame.minX + 1)
        XCTAssertLessThanOrEqual(info.frame.maxX, undo.frame.minX + 1)

        // Collapse Group Focus via trailing chevron.up -> returns to Timeline & Expand pill in header.
        let foldButton = element(app, "clove.detail.filmstrip.group.fold")
        XCTAssertTrue(foldButton.waitForExistence(timeout: 5))
        foldButton.tap()
        let expandPill = element(app, "clove.detail.expandGroup")
        XCTAssertTrue(expandPill.waitForExistence(timeout: 5))
        expandPill.tap()
        XCTAssertTrue(rejectPill.waitForExistence(timeout: 5))

        // Rotate to landscapeRight -> stays cleanly within safe bounds and horizontal pickers open above.
        XCUIDevice.shared.orientation = .landscapeRight
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 5))
        XCTAssertGreaterThanOrEqual(capsule.frame.minX, 0)
        XCTAssertLessThanOrEqual(capsule.frame.maxX, app.frame.maxX)

        element(app, "clove.detail.capsule.rating").tap()
        let stars = element(app, "clove.detail.capsule.stars")
        XCTAssertTrue(stars.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(stars.frame.width, stars.frame.height)
        XCTAssertLessThanOrEqual(stars.frame.maxY, capsule.frame.minY + 1)
        element(app, "clove.detail.capsule.stars.4").tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), stars))

        // Single tap on stage hides chrome including landscapeBottomRow, second tap restores it.
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), bottomRow))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        XCTAssertTrue(bottomRow.waitForExistence(timeout: 5))

        // Rotate back to portrait -> returns to stacked portrait layout and Back exits to Grid.
        XCUIDevice.shared.orientation = .portrait
        XCTAssertTrue(wait(NSPredicate(format: "exists == false"), bottomRow))
        XCTAssertTrue(capsule.waitForExistence(timeout: 5))
        XCTAssertTrue(filmstrip.waitForExistence(timeout: 5))
        back.tap()
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
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
        if open.exists {
            open.tap()
            let detail = element(app, "clove.detail")
            let grid = element(app, "clove.grid")
            let deadline = Date().addingTimeInterval(5)
            while Date() < deadline && !detail.exists && !grid.exists {
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            }
        }
        if element(app, "clove.detail").exists {
            let back = element(app, "clove.nav.back")
            if back.waitForExistence(timeout: 5) { back.tap() }
        }
        XCTAssertTrue(element(app, "clove.grid").waitForExistence(timeout: 10))
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
    func assertSameFrame(
        _ first: CGRect, _ second: CGRect, _ message: String, accuracy: CGFloat = 0.5
    ) {
        XCTAssertEqual(first.minX, second.minX, accuracy: accuracy, message)
        XCTAssertEqual(first.minY, second.minY, accuracy: accuracy, message)
        XCTAssertEqual(first.width, second.width, accuracy: accuracy, message)
        XCTAssertEqual(first.height, second.height, accuracy: accuracy, message)
    }

    @MainActor
    func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
