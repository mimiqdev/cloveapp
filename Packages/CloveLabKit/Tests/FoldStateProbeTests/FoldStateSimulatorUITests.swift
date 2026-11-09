#if FOLD_STATE_SIMULATOR_UI_TESTS
    import XCTest

    /// Run only through measure-simulator.sh's disposable project, never as a
    /// macOS package test. Uses the actual Lab screen and shared exporter.
    @MainActor
    final class FoldStateSimulatorUITests: XCTestCase {
        func testGeometryContinuityAndExport() throws {
            let app = XCUIApplication()
            app.launch()
            app.staticTexts["S7 · Fold state"].tap()
            let increment = app.buttons["clovelab.fold-state.increment"]
            XCTAssertTrue(increment.waitForExistence(timeout: 10))
            app.buttons["Start new run"].tap()
            increment.tap()
            let write = app.buttons["clovelab.fold-state.writeReport"]
            write.tap()
            // Rotate a normal iPhone to exercise the geometry path. This is
            // deliberately not described as a fold or a Duo measurement.
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(write.waitForExistence(timeout: 5))
            write.tap()
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(write.waitForExistence(timeout: 5))
            write.tap()
            // Returning to Fold state recreates the view but retains its on-disk event
            // journal. The exported history must show the changed State ID.
            app.navigationBars.buttons.firstMatch.tap()
            app.staticTexts["S7 · Fold state"].tap()
            XCTAssertTrue(write.waitForExistence(timeout: 5))
            write.tap()
        }
    }
#endif
