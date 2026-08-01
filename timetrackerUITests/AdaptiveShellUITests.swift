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

    private func launchApp(windowWidth: CGFloat? = nil) -> XCUIApplication {
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
        #if os(macOS)
        if let windowWidth {
            app.launchEnvironment["TIMETRACKER_UI_TEST_WINDOW_WIDTH"] = "\(windowWidth)"
            app.launchEnvironment["TIMETRACKER_UI_TEST_WINDOW_HEIGHT"] = "820"
        }
        #endif
        app.launch()
        addTeardownBlock {
            if app.state != .notRunning {
                app.terminate()
            }
        }
        #if os(macOS)
        let readyElement = app.descendants(matching: .any)["home.view"]
        #else
        let readyElement = app.otherElements["app.initialConfiguration.ready"]
        #endif
        XCTAssertTrue(
            readyElement.waitForExistence(timeout: 90),
            "The app never finished initial configuration."
        )
        return app
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

    private func attachScreenshot(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
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

    /// Repeated primary navigation must replace only the detail content. The
    /// surrounding NavigationStack stays alive so rapid sidebar use does not
    /// rebuild navigation infrastructure for every selection.
    func testRapidPrimaryDestinationSwitchingKeepsEachPageReachable() {
        let app = launchApp(windowWidth: 1180)
        let destinations = [
            ("sidebar.Inbox", "inbox.view"),
            ("sidebar.Tasks", "tasks.view"),
            ("sidebar.Pomodoro", "pomodoro.view"),
            ("sidebar.Analytics", "analytics.view"),
            ("sidebar.Today", "home.view"),
        ]

        activate(
            app.descendants(matching: .any)["sidebar.Analytics"],
            in: app
        )
        let analyticsDetailLink = app.descendants(matching: .any)["analytics.category.decisions"]
        XCTAssertTrue(
            analyticsDetailLink.waitForExistence(timeout: 15),
            "Analytics never exposed a detail route for the navigation reset check."
        )
        activate(analyticsDetailLink, in: app)
        XCTAssertTrue(
            app.descendants(matching: .any)["analytics.categoryDetail.decisions"]
                .waitForExistence(timeout: 10),
            "The Analytics detail route did not open."
        )
        activate(
            app.descendants(matching: .any)["sidebar.Today"],
            in: app
        )
        XCTAssertTrue(
            app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 10),
            "Changing primary destination did not clear the previous page's navigation path."
        )

        for _ in 0 ..< 3 {
            for (sidebarIdentifier, pageIdentifier) in destinations {
                let sidebarItem = app.descendants(matching: .any)[sidebarIdentifier]
                XCTAssertTrue(
                    sidebarItem.waitForExistence(timeout: 5),
                    "Missing primary sidebar destination \(sidebarIdentifier)."
                )
                activate(sidebarItem, in: app, timeout: 5)
                XCTAssertTrue(
                    app.descendants(matching: .any)[pageIdentifier]
                        .waitForExistence(timeout: 5),
                    "Primary destination \(pageIdentifier) did not become reachable."
                )
            }
        }

        attachScreenshot(app, named: "mac-rapid-primary-navigation")
    }
    #endif

    /// Mirrors `RootLayoutPolicy.regularShellMinimumWidth`.
    private static let shellBreakpoint: CGFloat = 720

    /// Today's Now section must survive whichever shell is chosen — the two
    /// shells build it from different section types, so a regression can hide
    /// in one and not the other.
    func testNowSectionRendersInWhicheverShellIsChosen() {
        let app = launchApp()

        XCTAssertTrue(
            app.descendants(matching: .any)["home.activeTimers"].waitForExistence(timeout: 15),
            "Today rendered without its Now section."
        )

        attachScreenshot(app, named: "today-now-section")
    }
}
