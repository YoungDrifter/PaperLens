import XCTest

/// The hidden-titlebar window runs the system double-click action itself, so a
/// double click on an app-drawn chrome control used to stretch the window.
/// Unit tests cannot see that window-level behavior; this exercises real clicks.
final class ChromeDoubleClickUITests: XCTestCase {
    override func setUpWithError() throws { continueAfterFailure = false }

    @MainActor
    func testDoubleClickingChromeControlsKeepsWindowSize() throws {
        let app = XCUIApplication()
        app.launchArguments += ["-AppleInterfaceStyle", "Light", "-AppleActionOnDoubleClick", "Maximize"]
        app.launch()

        let window = app.windows.firstMatch
        XCTAssertTrue(window.waitForExistence(timeout: 20))
        XCTAssertTrue(app.buttons["Recent Files"].waitForExistence(timeout: 10))
        Thread.sleep(forTimeInterval: 1.5)
        let original = window.frame

        // A single click still belongs to the control: the history panel opens.
        app.buttons["Recent Files"].click()
        XCTAssertTrue(app.staticTexts["Recent Files"].waitForExistence(timeout: 5),
                      "A single click on the history button must still open Recent Files")
        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.4)

        // Repeating that click must not reach the window's double-click action.
        app.buttons["Recent Files"].doubleClick()
        Thread.sleep(forTimeInterval: 0.9)
        XCTAssertEqual(window.frame, original, "Double clicking the history button must not resize the window")

        app.buttons["Back"].doubleClick()
        Thread.sleep(forTimeInterval: 0.9)
        XCTAssertEqual(window.frame, original, "Double clicking Back must not resize the window")

        app.typeKey(XCUIKeyboardKey.escape.rawValue, modifierFlags: [])
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(window.frame, original)
    }
}
