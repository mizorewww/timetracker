import XCTest

/// Proves the shell the user actually sees follows the available width.
///
/// `RootLayoutPolicy` unit tests cover the decision itself; these cover the
/// wiring — that each branch of `AppRootView` builds and presents the shell it
/// claims to. Run on an iPhone destination and an iPad destination to cover
/// both widths.
///
/// The shells are identified by the navigation affordance each one owns rather
/// than by a container identifier. `TabView`'s own `.accessibilityIdentifier`
/// does not surface as a queryable element under the iOS 26+ floating tab bar —
/// verified to be true before this refactor as well as after — so asserting on
/// it would test the SwiftUI version, not the app.
final class AdaptiveShellUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO",
        ]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()
        XCTAssertTrue(
            app.otherElements["app.initialConfiguration.ready"].waitForExistence(timeout: 90),
            "The app never finished initial configuration."
        )
        return app
    }

    /// The sidebar is the affordance only the split shell has.
    private func sidebar(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["sidebar.today"]
    }

    /// Today's toolbar Settings button exists only in the compact shell; the
    /// split shell reaches Settings through the sidebar or the Settings scene.
    private func compactSettingsButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.open"]
    }

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Exactly one shell must be presented, and it must be the one this
    /// destination's width calls for.
    func testExactlyOneShellIsPresentedAndItMatchesTheWindowWidth() {
        let app = launchApp()

        let hasSidebar = sidebar(in: app).waitForExistence(timeout: 15)
        let hasCompactSettings = compactSettingsButton(in: app).exists

        XCTAssertNotEqual(
            hasSidebar,
            hasCompactSettings,
            """
            Expected exactly one shell. sidebar=\(hasSidebar) \
            compactSettings=\(hasCompactSettings).
            Hierarchy:
            \(app.debugDescription)
            """
        )

        // The shell must agree with the width the window actually has.
        let width = app.windows.firstMatch.frame.width
        let breakpoint: CGFloat = 720
        if width >= breakpoint {
            XCTAssertTrue(
                hasSidebar,
                "A \(width)pt window is wide enough for the split shell but got the compact one."
            )
        } else {
            XCTAssertTrue(
                hasCompactSettings,
                "A \(width)pt window is too narrow for the split shell but got it anyway."
            )
        }

        attachScreenshot(app, named: hasSidebar ? "shell-regular" : "shell-compact")
    }

    /// Today must render at either width, so neither shell silently loses the
    /// screen the app opens on.
    func testTodayRendersInWhicheverShellIsChosen() {
        let app = launchApp()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15),
            "Today did not render."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["home.activeTimers"].waitForExistence(timeout: 15),
            "Today rendered without its Now section."
        )

        attachScreenshot(app, named: "today-current-shell")
    }

    /// The split shell must offer every destination in its sidebar.
    func testRegularShellExposesEveryDestination() throws {
        let app = launchApp()
        try XCTSkipUnless(
            sidebar(in: app).waitForExistence(timeout: 15),
            "This destination is too narrow for the split shell."
        )

        for identifier in ["sidebar.today", "sidebar.inbox", "sidebar.tasks", "sidebar.analytics"] {
            XCTAssertTrue(
                app.descendants(matching: .any)[identifier].waitForExistence(timeout: 5),
                "Missing \(identifier) in the split shell sidebar."
            )
        }

        attachScreenshot(app, named: "regular-shell-sidebar")
    }
}
