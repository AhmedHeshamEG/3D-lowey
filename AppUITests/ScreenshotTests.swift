import UIKit
import XCTest

/// App Store screenshots (STUDIO §10): the iPad 13" set from the shipped samples, and the iPhone 6.9" face companion.
/// CI runs them on those simulators and uploads the attachments named `AppStore-<device>-<nn>-<screen>`.
final class ScreenshotTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-ui-testing", "-ui-testing-sample", "-ui-testing-screenshots"]
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func element(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)[identifier].firstMatch
    }

    private func tap(_ identifier: String) {
        let target = element(identifier)
        XCTAssertTrue(target.waitForExistence(timeout: 15), "\(identifier) is missing")
        target.tap()
    }

    /// Lets the renderer settle (models load, the playhead lands) before a picture. A plain wait: querying the UI
    /// tree while thumbnails render can itself time out.
    private func settle(_ seconds: TimeInterval = 2) {
        _ = XCTWaiter.wait(for: [XCTestExpectation(description: "settle")], timeout: seconds)
    }

    func testIPadScreenshots() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "the iPad set")
        XCUIDevice.shared.orientation = .landscapeLeft
        app.launch()
        XCTAssertTrue(element("project-Welcome island").waitForExistence(timeout: 60), "the samples are on Home")
        settle()
        capture("AppStore-iPad-01-Home")
        tap("project-Enigma — the story")
        XCTAssertTrue(app.otherElements["stage"].waitForExistence(timeout: 30))
        settle(4)
        capture("AppStore-iPad-02-Stage")
        tap("director-view")
        settle(3)
        capture("AppStore-iPad-03-Director")
        tap("Look")
        settle()
        capture("AppStore-iPad-04-Looks")
        tap("Look")
        tap("Cast")
        settle()
        capture("AppStore-iPad-05-Cast")
        tap("Cast")
        tap("Actions")
        tap("open-export")
        XCTAssertTrue(element("export-hd1080").waitForExistence(timeout: 10))
        settle()
        capture("AppStore-iPad-06-Export")
    }

    func testIPhoneCompanion() throws {
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .phone, "the iPhone set")
        app.launch()
        XCTAssertTrue(element("companion-status").waitForExistence(timeout: 30))
        settle()
        capture("AppStore-iPhone-01-Companion")
    }
}
