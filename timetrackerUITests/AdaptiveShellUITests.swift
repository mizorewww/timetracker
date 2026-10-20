import XCTest

/// Proves the shell the user actually sees follows the available width.
///
/// `RootLayoutPolicy` unit tests cover the decision itself; these cover the
/// wiring — that the shell root (`ShellController` on iOS, `AppRootView` on
/// macOS) builds and presents the shell it claims to. Run on an iPhone
/// destination and an iPad destination to cover both widths.
///
/// The shells are identified by the navigation affordance each one owns rather
/// than by a container identifier, which the iOS 26+ floating tab bar does not
/// surface as a queryable element.
final class AdaptiveShellUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    private func launchApp(windowWidth: CGFloat? = nil) -> XCUIApplication {
        launchDemoApp(windowSize: windowWidth.map { CGSize(width: $0, height: 820) })
    }

    private func activate(
        _ element: XCUIElement,
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) {
        XCTAssertTrue(element.waitForExistence(timeout: timeout))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 3))
        element.click()
    }

    /// Today's toolbar Settings button is the reliable discriminator: only
    /// `CompactHomeView` draws it. The split shell reaches Settings through the
    /// sidebar or, on macOS, the Settings scene.
    ///
    /// The sidebar itself is not usable as the signal — `NavigationSplitView`
    /// collapses it behind the system toggle in iPad portrait, so its absence
    /// says nothing about which shell was chosen.
    private func compactSettingsButton(in app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any)["settings.open"]
    }

    /// The presented shell must be the one this window's width calls for.
    ///
    /// This is the contract `RootLayoutPolicy` promises, checked end to end
    /// against the width the window actually has rather than against the device
    /// the test happens to run on.
    func testPresentedShellMatchesTheWindowWidth() {
        let app = launchApp()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15),
            "Today never rendered, so no shell could be identified."
        )

        let isCompactShell = compactSettingsButton(in: app).exists
        let width = app.windows.firstMatch.frame.width

        if width >= Self.shellBreakpoint {
            XCTAssertFalse(
                isCompactShell,
                """
                A \(width)pt window is wide enough for the split shell but got \
                the compact one.
                Hierarchy:
                \(app.debugDescription)
                """
            )
        } else {
            XCTAssertTrue(
                isCompactShell,
                """
                A \(width)pt window is too narrow for the split shell but got \
                it anyway.
                Hierarchy:
                \(app.debugDescription)
                """
            )
        }

        attachScreenshot(app, named: isCompactShell ? "shell-compact" : "shell-regular")
    }

    #if os(macOS)
    /// A narrow Mac uses the shared compact product shell, but Settings remains
    /// a native macOS scene rather than falling back to an in-window sheet.
    func testNarrowMacKeepsNativeSettingsCapability() {
        let app = launchApp(windowWidth: 680)

        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15)
        )
        let settingsButton = compactSettingsButton(in: app)
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 5))
        XCTAssertLessThan(app.windows.firstMatch.frame.width, Self.shellBreakpoint)

        activate(settingsButton, in: app)

        XCTAssertTrue(
            app.descendants(matching: .any)["settings.view"].waitForExistence(timeout: 20),
            "The compact Mac shell did not route Settings through its native scene."
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"].exists,
            "Opening the native Settings scene replaced the main compact workspace."
        )
        attachScreenshot(app, named: "mac-compact-native-settings")
    }

    #endif

    /// Mirrors `RootLayoutPolicy.regularShellMinimumWidth`.
    private static let shellBreakpoint: CGFloat = 720

    /// Today's Now section must survive whichever shell is chosen — the two
    /// shells host it in different containers (list section vs. card), so a
    /// regression can hide in one and not the other.
    func testNowSectionRendersInWhicheverShellIsChosen() {
        let app = launchApp()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.activeTimers"].waitForExistence(timeout: 15),
            "Today rendered without its Now section."
        )

        attachScreenshot(app, named: "today-now-section")
    }
}
