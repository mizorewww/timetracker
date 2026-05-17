import XCTest

final class timetrackerClickableSurfaceUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        XCUIApplication().terminate()
    }

    @MainActor
    func testRootDestinationsAreClickable() throws {
        let app = launchApp()

        let destinations: [RootDestination] = [
            RootDestination(rawValue: "Today", title: "首页", readyIdentifier: "home.startTimer"),
            RootDestination(rawValue: "Inbox", title: "收件箱", readyIdentifier: "inbox.view"),
            RootDestination(rawValue: "Tasks", title: "任务", readyIdentifier: "tasks.view"),
            RootDestination(rawValue: "Pomodoro", title: "番茄钟", readyIdentifiers: ["pomodoro.active", "pomodoro.timerFace", "pomodoro.startFocus"]),
            RootDestination(rawValue: "Analytics", title: "分析", readyIdentifier: "analytics.homeSummary"),
            RootDestination(rawValue: "Settings", title: "设置", readyIdentifier: "settings.view")
        ]

        for destination in destinations {
            openRootDestination(destination, in: app)
            XCTAssertTrue(destinationIsReady(destination, in: app), "\(destination.rawValue) did not become ready.")
            assertAppStillRunning(app, after: destination.rawValue)
        }
    }

    @MainActor
    func testTaskRowsOpenDetailsWithoutCrashing() throws {
        let taskTargets: [(title: String, searchToken: String)] = [
            ("Time Tracker App", "Tracker"),
            ("Design System", "System"),
            ("Design macOS UI", "macOS"),
            ("Design iOS UI", "iOS"),
            ("Implementation", "Implementation"),
            ("SwiftData Ledger", "SwiftData"),
            ("Analytics Charts", "Analytics"),
            ("iCloud Sync", "iCloud"),
            ("Client Work", "Client"),
            ("Team Meeting", "Team"),
            ("Requirements Review", "Requirements"),
            ("Study", "Study"),
            ("Read Apple HIG", "HIG"),
            ("SwiftData Docs", "Docs")
        ]

        for target in taskTargets {
            let app = launchApp()
            openRootDestination(RootDestination(rawValue: "Tasks", title: "任务", readyIdentifier: "tasks.view"), in: app)
            _ = searchForTask(target.searchToken, in: app)

            let title = target.title
            let identifier = "tasks.task.\(title)"
            guard tapElement(identifier: identifier, in: app, scrollIfNeeded: true) else {
                XCTFail("Could not tap visible task row \(title).")
                return
            }

            XCTAssertTrue(taskDetailIsReady(in: app), "Task detail did not open for \(title).")
            assertAppStillRunning(app, after: "task row \(title)")
            app.terminate()
        }
    }

    @MainActor
    func testAnalyticsCategoriesOpenDetailsAndPeriodControlsWithoutCrashing() throws {
        let categories = ["overview", "time", "tasks", "pomodoro", "decisions", "quality"]
        for category in categories {
            let app = launchApp()
            openRootDestination(RootDestination(rawValue: "Analytics", title: "分析", readyIdentifier: "analytics.homeSummary"), in: app)

            let rowIdentifier = "analytics.category.\(category)"
            guard tapElement(identifier: rowIdentifier, in: app, scrollIfNeeded: true) else {
                XCTFail("Could not tap analytics category \(category).")
                return
            }

            XCTAssertTrue(waitForIdentifier("analytics.detail.\(category)", in: app), "Analytics detail did not open for \(category).")
            assertAppStillRunning(app, after: "analytics category \(category)")

            _ = tapElement(identifier: "analytics.periodControl", in: app, timeout: 1)
            assertAppStillRunning(app, after: "analytics period controls in \(category)")
            app.terminate()
        }
    }

    @MainActor
    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch"
        ]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()
        app.activate()
        return app
    }

    @MainActor
    private func openRootDestination(_ destination: RootDestination, in app: XCUIApplication) {
        if destinationIsReady(destination, in: app, timeout: 0.5) {
            return
        }

        if destination.rawValue == "Settings", tapElement(identifier: "settings.open", in: app, timeout: 1) {
            return
        }

        if tapElement(identifier: "sidebar.\(destination.rawValue)", in: app, timeout: 1) {
            return
        }

        if tapPhoneDestination(destination.rawValue, in: app) {
            return
        }

        if tapElement(identifier: destination.title, in: app, timeout: 1) {
            return
        }

        XCTFail("Could not open \(destination.rawValue).")
    }

    @MainActor
    private func tapPhoneDestination(_ rawValue: String, in app: XCUIApplication) -> Bool {
        let identifier = "phone.bottom.\(rawValue)"
        if tapElement(identifier: identifier, in: app, timeout: 1) {
            return true
        }

        let bottomBar = app.descendants(matching: .any)["phone.bottomBar"].firstMatch
        guard bottomBar.waitForExistence(timeout: 1) else {
            return false
        }

        for _ in 0..<2 {
            bottomBar.swipeLeft()
            if tapElement(identifier: identifier, in: app, timeout: 1) {
                return true
            }
        }

        for _ in 0..<2 {
            bottomBar.swipeRight()
            if tapElement(identifier: identifier, in: app, timeout: 1) {
                return true
            }
        }

        return false
    }

    @MainActor
    private func tapElement(
        identifier: String,
        in app: XCUIApplication,
        timeout: TimeInterval = 3,
        scrollIfNeeded: Bool = false
    ) -> Bool {
        if let element = hittableElement(identifier: identifier, in: app, timeout: timeout) {
            element.tap()
            return true
        }

        guard scrollIfNeeded else { return false }

        for _ in 0..<8 {
            guard scrollContent(in: app, direction: .up) else { return false }
            if let element = hittableElement(identifier: identifier, in: app, timeout: 0.25) {
                element.tap()
                return true
            }
        }

        for _ in 0..<8 {
            guard scrollContent(in: app, direction: .down) else { return false }
            if let element = hittableElement(identifier: identifier, in: app, timeout: 0.25) {
                element.tap()
                return true
            }
        }

        return false
    }

    @MainActor
    private func hittableElement(identifier: String, in app: XCUIApplication, timeout: TimeInterval) -> XCUIElement? {
        let preferredQueries = [
            app.buttons[identifier].firstMatch,
            app.cells[identifier].firstMatch,
            app.otherElements[identifier].firstMatch,
            app.staticTexts[identifier].firstMatch
        ]

        let matches = app.descendants(matching: .any).matching(identifier: identifier)
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            for element in preferredQueries {
                if element.exists, element.isHittable {
                    return element
                }
            }

            let count = min(matches.count, 32)
            for index in 0..<count {
                let element = matches.element(boundBy: index)
                if element.exists, element.isHittable {
                    return element
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    @MainActor
    private func searchForTask(_ title: String, in app: XCUIApplication) -> Bool {
        if let searchField = hittableSearchField(in: app) {
            searchField.tap()
            searchField.typeText(title)
            commitSearchText(in: app)
            return true
        }

        #if os(macOS)
        app.typeKey("f", modifierFlags: .command)
        if let searchField = hittableSearchField(in: app) {
            searchField.tap()
            searchField.typeText(title)
            commitSearchText(in: app)
            return true
        }
        #endif

        return false
    }

    @MainActor
    private func hittableSearchField(in app: XCUIApplication) -> XCUIElement? {
        let searchFields = app.searchFields
        let deadline = Date().addingTimeInterval(1)
        repeat {
            let count = min(searchFields.count, 8)
            for index in 0..<count {
                let field = searchFields.element(boundBy: index)
                if field.exists, field.isHittable {
                    return field
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    @MainActor
    private func commitSearchText(in app: XCUIApplication) {
        #if os(macOS)
        app.typeKey(.return, modifierFlags: [])
        #endif
    }

    @MainActor
    private func scrollContent(in app: XCUIApplication, direction: ScrollDirection) -> Bool {
        let containers = [
            app.descendants(matching: .any)["tasks.view"].firstMatch,
            app.descendants(matching: .any)["analytics.homeSummary"].firstMatch,
            app.scrollViews.firstMatch,
            app.collectionViews.firstMatch,
            app.tables.firstMatch,
            app.windows.firstMatch
        ]

        for container in containers where container.exists && container.isHittable {
            switch direction {
            case .up:
                container.swipeUp()
            case .down:
                container.swipeDown()
            }
            return true
        }

        return false
    }

    @MainActor
    private func waitForIdentifier(_ identifier: String, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        app.descendants(matching: .any)[identifier].firstMatch.waitForExistence(timeout: timeout)
    }

    @MainActor
    private func destinationIsReady(_ destination: RootDestination, in app: XCUIApplication, timeout: TimeInterval = 5) -> Bool {
        destination.readyIdentifiers.contains { waitForIdentifier($0, in: app, timeout: timeout) }
    }

    @MainActor
    private func taskDetailIsReady(in app: XCUIApplication) -> Bool {
        app.buttons["task.detail.addTime"].waitForExistence(timeout: 4) ||
        app.buttons["补录时间"].waitForExistence(timeout: 1) ||
        app.buttons["添加时间"].waitForExistence(timeout: 1) ||
        app.buttons["Add Time"].waitForExistence(timeout: 1)
    }

    @MainActor
    private func assertAppStillRunning(_ app: XCUIApplication, after action: String, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertNotEqual(app.state, .notRunning, "App stopped running after \(action).", file: file, line: line)
    }
}

private struct RootDestination {
    let rawValue: String
    let title: String
    let readyIdentifiers: [String]

    init(rawValue: String, title: String, readyIdentifier: String) {
        self.rawValue = rawValue
        self.title = title
        readyIdentifiers = [readyIdentifier]
    }

    init(rawValue: String, title: String, readyIdentifiers: [String]) {
        self.rawValue = rawValue
        self.title = title
        self.readyIdentifiers = readyIdentifiers
    }
}

private enum ScrollDirection {
    case up
    case down
}
