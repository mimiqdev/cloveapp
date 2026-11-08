import XCTest

final class CloveUITests: XCTestCase {
    @MainActor
    func testRootViewIsVisible() {
        let app = XCUIApplication()
        app.launch()

        XCTAssertTrue(
            app.otherElements["clove.root"].waitForExistence(timeout: 30),
            "The Clove root view did not appear"
        )
    }
}
