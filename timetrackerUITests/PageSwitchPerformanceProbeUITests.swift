import XCTest

// TEST-SCAFFOLD: Docs/ImplementationContexts/2026-08-06-page-switching-performance.md
// — remove when the page-switching performance work closes out. Manual
// measurement driver; latency comes from the app's PERF-TRACE lines in the
// xcodebuild log (SWITCH-BEGIN → APPEAR delta), not from AX timing.

final class PageSwitchPerformanceProbeUITests: XCTestCase {
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
    }

    override func tearDown() {
        // The simulator is deleted by the run harness right after the test;
        // copy the app's trace file out while it still exists.
        copyAppTraceFile()
        super.tearDown()
    }

    private func copyAppTraceFile() {
        guard let udid = ProcessInfo.processInfo.environment["SIMULATOR_UDID"]
        else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        task.arguments = [
            "simctl", "get_app_container", udid,
            "me.mezorewww.timetracker", "data",
        ]
        let pipe = Pipe()
        task.standardOutput = pipe
        do {
            try task.run()
        } catch {
            return
        }
        task.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let container = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let container, container.isEmpty == false else { return }
        let trace = URL(fileURLWithPath: container)
            .appendingPathComponent("Documents/perf-trace.log")
        guard FileManager.default.fileExists(atPath: trace.path) else { return }
        let stamp = Int(Date().timeIntervalSince1970)
        try? FileManager.default.copyItem(
            at: trace,
            to: URL(fileURLWithPath: "/tmp/timetracker-perf-trace-\(stamp).log")
        )
        print("PERF-TRACE-COPIED /tmp/timetracker-perf-trace-\(stamp).log")
    }

    private func launchApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "--uitesting-high-density-ui",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO",
        ]
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()
        addTeardownBlock {
            if app.state != .notRunning {
                app.terminate()
            }
        }
        return app
    }

    func testTabSwitchLatencyDenseFixture() throws {
        let app = launchApp()

        let ready = app.descendants(matching: .any)["app.initialConfiguration.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 240))
        let today = app.descendants(matching: .any)["home.view"]
        XCTAssertTrue(today.waitForExistence(timeout: 60))

        let tabs: [(id: String, page: String, marker: String)] = [
            ("phone.tab.tasks", "tasks.view", "tasks"),
            ("phone.tab.inbox", "inbox.view", "inbox"),
            ("phone.tab.focus", "pomodoro.view", "pomodoro"),
            ("phone.tab.analytics", "analytics.view", "analytics"),
            ("phone.tab.today", "home.view", "today"),
        ]

        // Three full rounds of tab switching: first round mounts each tab for
        // the first time (cold), later rounds hit the mounted tabs (warm).
        for round in 0 ..< 3 {
            print("PERF-ROUND \(round)")
            for tab in tabs {
                restoreTabBar(app)
                let button = app.buttons[tab.id].firstMatch
                XCTAssertTrue(button.waitForExistence(timeout: 10))
                let tapStart = Date()
                button.tap()
                let page = app.descendants(matching: .any)[tab.page]
                let appeared = page.waitForExistence(timeout: 30)
                let elapsed = Date().timeIntervalSince(tapStart)
                print(
                    "PERF-AX \(tab.marker) round=\(round) "
                        + "elapsed=\(String(format: "%.3f", elapsed)) "
                        + "appeared=\(appeared)"
                )
                XCTAssertTrue(appeared, "Round \(round) page \(tab.marker) never appeared.")
                // Hold the switch window open so host-side sample windows
                // overlap the first-mount work (align by timestamp).
                RunLoop.current.run(until: Date().addingTimeInterval(4))
            }
        }
    }

    private func restoreTabBar(_ app: XCUIApplication) {
        for _ in 0 ..< 12 {
            app.swipeDown(velocity: .fast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.25))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    }
}
