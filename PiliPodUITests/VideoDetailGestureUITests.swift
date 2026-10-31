import XCTest

final class VideoDetailGestureUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openDetail() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest-video-detail-gestures"]
        app.launch()
        app.buttons["gesture.open"].tap()
        XCTAssertTrue(app.staticTexts["gesture.tab.intro"].waitForExistence(timeout: 5))
        return app
    }

    @MainActor
    func testTabSwipesAndContentBack() {
        let app = openDetail()
        let left = app.coordinate(withNormalizedOffset: CGVector(dx: 0.15, dy: 0.65))
        let right = app.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.65))
        right.press(forDuration: 0.05, thenDragTo: left)
        XCTAssertTrue(app.staticTexts["gesture.tab.comments"].waitForExistence(timeout: 5))
        left.press(forDuration: 0.05, thenDragTo: right)
        XCTAssertTrue(app.staticTexts["gesture.tab.intro"].waitForExistence(timeout: 5))
        let backStart = app.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.65))
        let backEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.68))
        backStart.press(forDuration: 0.05, thenDragTo: backEnd)
        XCTAssertTrue(app.buttons["gesture.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["gesture.tab.intro"].exists)
    }

    @MainActor
    func testEdgeBack() {
        let app = openDetail()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.65))
        let end = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.65))
        start.press(forDuration: 0.05, thenDragTo: end)
        XCTAssertTrue(app.buttons["gesture.open"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["gesture.tab.intro"].exists)
    }

    @MainActor
    func testVerticalScrollDoesNotSwitchTabs() {
        let app = openDetail()
        XCTAssertTrue(app.staticTexts["gesture.intro.0"].isHittable)
        app.swipeUp()
        XCTAssertTrue(app.staticTexts["gesture.tab.intro"].exists)
        XCTAssertFalse(app.staticTexts["gesture.intro.0"].isHittable)
    }
}
