import XCTest

final class timetrackerStressDataUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testStressDataProfileLaunchesCoreSurfaces() throws {
        let app = launchStressApp()

        XCTAssertTrue(
            openDestination("Tasks", title: "任务", readyIdentifier: "tasks.view", in: app),
            app.debugDescription
        )
        XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS %@", "Stress")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .notRunning)

        XCTAssertTrue(openDestination("Analytics", title: "分析", readyIdentifier: "analytics.homeSummary", in: app))
        XCTAssertTrue(app.descendants(matching: .any)["analytics.category.overview"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertNotEqual(app.state, .notRunning)
    }

    @MainActor
    private func launchStressApp() -> XCUIApplication {
        let app = XCUIApplication()
        let environment = ProcessInfo.processInfo.environment
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-TimeTrackerAutomaticDemoDataModeOverride", "off",
            "-TimeTrackerStressDataProfile", environment["TIMETRACKER_STRESS_PROFILE"] ?? "compact",
            "-TimeTrackerStressRootCount", environment["TIMETRACKER_STRESS_ROOTS"] ?? "",
            "-TimeTrackerStressMaxDepth", environment["TIMETRACKER_STRESS_DEPTH"] ?? "",
            "-TimeTrackerStressChildrenPerNode", environment["TIMETRACKER_STRESS_CHILDREN"] ?? "",
            "-TimeTrackerStressChecklistItemsPerTask", environment["TIMETRACKER_STRESS_CHECKLIST_ITEMS"] ?? "",
            "-TimeTrackerStressSegmentsPerTask", environment["TIMETRACKER_STRESS_SEGMENTS"] ?? "",
            "-TimeTrackerStressCategoryCount", environment["TIMETRACKER_STRESS_CATEGORIES"] ?? "",
            "-TimeTrackerStressInboxItemCount", environment["TIMETRACKER_STRESS_INBOX_ITEMS"] ?? "",
            "-TimeTrackerStressCountdownEventCount", environment["TIMETRACKER_STRESS_COUNTDOWNS"] ?? ""
        ]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func openDestination(
        _ rawValue: String,
        title: String,
        readyIdentifier: String,
        in app: XCUIApplication
    ) -> Bool {
        if app.descendants(matching: .any)[readyIdentifier].firstMatch.waitForExistence(timeout: 0.5) {
            return true
        }

        if tapElement(identifier: "sidebar.\(rawValue)", in: app, timeout: 2) {
            return app.descendants(matching: .any)[readyIdentifier].firstMatch.waitForExistence(timeout: 5)
        }

        if tapPhoneDestination(rawValue, in: app) {
            return app.descendants(matching: .any)[readyIdentifier].firstMatch.waitForExistence(timeout: 5)
        }

        if tapElement(identifier: title, in: app, timeout: 2) {
            return app.descendants(matching: .any)[readyIdentifier].firstMatch.waitForExistence(timeout: 5)
        }

        return false
    }

    @MainActor
    private func tapPhoneDestination(_ rawValue: String, in app: XCUIApplication) -> Bool {
        let identifier = "phone.bottom.\(rawValue)"
        if tapElement(identifier: identifier, in: app, timeout: 1) {
            return true
        }

        let bottomBar = app.descendants(matching: .any)["phone.bottomBar"].firstMatch
        guard bottomBar.waitForExistence(timeout: 1) else { return false }

        for _ in 0..<2 {
            bottomBar.swipeLeft()
            if tapElement(identifier: identifier, in: app, timeout: 1) {
                return true
            }
        }
        return false
    }

    @MainActor
    private func tapElement(identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> Bool {
        let preferredQueries: [XCUIElement]
        if identifier.hasPrefix("sidebar.") {
            preferredQueries = [
                app.staticTexts[identifier].firstMatch,
                app.buttons[identifier].firstMatch,
                app.cells[identifier].firstMatch,
                app.otherElements[identifier].firstMatch
            ]
        } else {
            preferredQueries = [
                app.buttons[identifier].firstMatch,
                app.cells[identifier].firstMatch,
                app.otherElements[identifier].firstMatch,
                app.staticTexts[identifier].firstMatch
            ]
        }
        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        let deadline = Date().addingTimeInterval(timeout)

        repeat {
            for element in preferredQueries where element.exists && element.isHittable {
                element.tap()
                return true
            }
            for element in preferredQueries where element.exists && hasVisibleFrame(element) {
                element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                return true
            }
            let count = min(matches.count, 24)
            for index in 0..<count {
                let element = matches.element(boundBy: index)
                if element.exists && element.isHittable {
                    element.tap()
                    return true
                }
                if element.exists && hasVisibleFrame(element) {
                    element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return false
    }

    @MainActor
    private func hasVisibleFrame(_ element: XCUIElement) -> Bool {
        !element.frame.isEmpty && element.frame.width > 0 && element.frame.height > 0
    }
}
