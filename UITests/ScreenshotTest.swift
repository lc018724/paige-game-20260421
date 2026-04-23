import XCTest

/// Launches Thread, taps PLAY, waits for the game scene, then saves a screenshot.
/// Run with: xcodebuild test -scheme Thread -destination 'id=...' -only-testing ThreadUITests/ScreenshotTest/testGameScreenshot
final class ScreenshotTest: XCTestCase {

    func testGameScreenshot() throws {
        let app = XCUIApplication()
        app.launch()

        // Tap the PLAY button on the title screen.
        let playButton = app.buttons["PLAY"]
        XCTAssertTrue(playButton.waitForExistence(timeout: 5))
        playButton.tap()

        // Give the game scene a moment to render the ring.
        Thread.sleep(forTimeInterval: 1.5)

        // Capture and attach screenshot.
        let screenshot = app.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "game_scene"
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
