#if S7_SIMULATOR_UI_TESTS
    import XCTest

    /// Run only through measure-simulator.sh's disposable project, never as a
    /// macOS package test. Uses the actual Lab screen and shared exporter.
    @MainActor
    final class S7SimulatorUITests: XCTestCase {
        func testGeometryContinuityAndExport() throws {
            let app = XCUIApplication()
            app.launch()
            app.staticTexts["S7"].tap()
            let increment = app.buttons["clovelab.s7.increment"]
            XCTAssertTrue(increment.waitForExistence(timeout: 10))
            app.buttons["Start new run"].tap()
            increment.tap()
            let write = app.buttons["clovelab.s7.writeReport"]
            write.tap()
            // Rotate a normal iPhone to exercise the geometry path. This is
            // deliberately not described as a fold or a Duo measurement.
            XCUIDevice.shared.orientation = .landscapeLeft
            XCTAssertTrue(write.waitForExistence(timeout: 5))
            write.tap()
            XCUIDevice.shared.orientation = .portrait
            XCTAssertTrue(write.waitForExistence(timeout: 5))
            write.tap()
            // Returning to S7 recreates the view but retains its on-disk event
            // journal. The exported history must show the changed State ID.
            app.navigationBars.buttons.firstMatch.tap()
            app.staticTexts["S7"].tap()
            XCTAssertTrue(write.waitForExistence(timeout: 5))
            write.tap()
        }
    }
#endif
