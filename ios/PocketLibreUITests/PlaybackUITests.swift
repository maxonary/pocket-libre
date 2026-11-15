import XCTest

final class PlaybackUITests: XCTestCase {
    func testInlinePlaybackAndSeek() throws {
        let app = XCUIApplication()
        app.launch()
        let row = app.buttons.containing(.staticText, identifier: "Player-Test · synthetischer Ton").firstMatch
        try XCTSkipUnless(row.waitForExistence(timeout: 5), "Seed the documented synthetic simulator fixture before this optional UI test.")
        if !row.isHittable { app.swipeUp() }
        row.tap()
        let play = app.buttons["Abspielen"]
        if !play.isHittable { app.swipeUp() }
        XCTAssertTrue(play.waitForExistence(timeout: 5))
        play.tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        func seconds() -> Int {
            let parts = app.staticTexts["playback.elapsed"].label.split(separator: ":").compactMap { Int($0) }
            return parts.reduce(0) { $0 * 60 + $1 }
        }
        let before = seconds()
        app.buttons["15 Sekunden vor"].tap()
        XCTAssertEqual(seconds() - before, 15, accuracy: 1)
        app.buttons["15 Sekunden zurück"].tap()
        XCTAssertEqual(seconds(), before, accuracy: 1)
        let slider = app.sliders["Wiedergabeposition"]
        slider.adjust(toNormalizedSliderPosition: 0.5)
        XCTAssertEqual(seconds(), 17, accuracy: 2)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Inline playback"; screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
