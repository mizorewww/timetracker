import XCTest

// TEST-SCAFFOLD: Docs/ImplementationContexts/2026-08-05-ui-component-performance.md
// — remove when the UI component/page performance work closes out. This class is a
// manual measurement driver, not a regression contract: it needs an external
// /usr/bin/sample loop on the host to be meaningful, and it cannot pass alone.

/// Manual performance probe for the UI performance work.
///
/// Protocol (host side):
/// 1. Launch this test via the Makefile UI runner (Debug + dense seed args below).
/// 2. While it runs, attach `/usr/bin/sample` windows to the app process
///    (found via `pgrep -f "CoreSimulator/Devices/<UDID>/data/Containers"`).
/// 3. The test writes phase markers to /tmp/timetracker-perf-phases.jsonl with
///    epoch start/end; correlate sample windows with phases by timestamp.
final class PerformanceProbeUITests: XCTestCase {
    private var markerFile: URL {
        URL(fileURLWithPath: "/tmp/timetracker-perf-phases.jsonl")
    }

    private var swipeDurations: [String: [TimeInterval]] = [:]

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        try? FileManager.default.removeItem(at: markerFile)
        swipeDurations = [:]
    }

    override func tearDown() {
        // Dump swipe latency summary as a phase marker so the host aggregator
        // can include it in the report.
        let summary = swipeDurations.mapValues { values in
            let sorted = values.sorted()
            return [
                "count": values.count,
                "median_ms": Int((sorted[sorted.count / 2] ?? 0) * 1000),
                "p90_ms": Int((sorted[min(values.count - 1, sorted.count * 9 / 10)] ?? 0) * 1000),
                "max_ms": Int((sorted.last ?? 0) * 1000),
            ]
        }
        if let data = try? JSONSerialization.data(withJSONObject: summary),
           let text = String(data: data, encoding: .utf8)
        {
            print("PERF-SWIPE-SUMMARY \(text)")
        }
        super.tearDown()
    }

    private func launchApp(
        dense: Bool = true
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitesting",
            "-ApplePersistenceIgnoreState", "YES",
            "-AppleLanguages", "(en)",
            "-AppleLocale", "en_US",
            "-TimeTrackerAutomaticDemoDataModeOverride", "replaceOnLaunch",
            "-TimeTrackerAutomaticDemoSeedingDisabled", "NO",
        ]
        if dense {
            app.launchArguments.append("--uitesting-high-density-ui")
        }
        app.launchEnvironment["ApplePersistenceIgnoreState"] = "YES"
        app.launch()
        addTeardownBlock {
            if app.state != .notRunning {
                app.terminate()
            }
        }
        return app
    }

    /// Control run: plain demo seed, Today must appear quickly. Validates the
    /// probe driver itself; if this fails the harness is broken, not the app.
    func testControlPlainLaunchShowsToday() throws {
        let app = launchApp(dense: false)

        let ready = app.descendants(matching: .any)["app.initialConfiguration.ready"]
        XCTAssertTrue(ready.waitForExistence(timeout: 120))
        let todayStart = Date()
        let todayVisible = app.descendants(matching: .any)["home.view"]
            .waitForExistence(timeout: 30)
        print(
            "PERF-CONTROL-TODAY elapsed=\(Date().timeIntervalSince(todayStart)) "
                + "visible=\(todayVisible)"
        )
        XCTAssertTrue(todayVisible, "Plain launch must show Today quickly.")
    }

    func testDenseTodayScrollAndPageTraversal() throws {
        let app = launchApp()

        let ready = app.descendants(matching: .any)["app.initialConfiguration.ready"]
        let readyStart = Date()
        XCTAssertTrue(
            ready.waitForExistence(timeout: 240),
            "The app never finished initial configuration with the dense fixture."
        )
        print("PERF-READY elapsed=\(Date().timeIntervalSince(readyStart))")

        let todayStart = Date()
        var todayVisible = app.descendants(matching: .any)["home.view"]
            .waitForExistence(timeout: 30)
        if todayVisible == false {
            // Periodic retry with tree dumps so the host can see what the app
            // is actually presenting while Today is slow to appear.
            for attempt in 1 ... 5 {
                dumpAXTree(app, to: "/tmp/timetracker-ax-tree-\(attempt).txt")
                print(
                    "PERF-TODAY-RETRY \(attempt) elapsed="
                        + "\(Date().timeIntervalSince(todayStart))"
                )
                todayVisible = app.descendants(matching: .any)["home.view"]
                    .waitForExistence(timeout: 20)
                if todayVisible { break }
            }
        }
        print(
            "PERF-TODAY elapsed=\(Date().timeIntervalSince(todayStart)) "
                + "visible=\(todayVisible)"
        )
        if todayVisible == false {
            throw XCTSkip(
                "Today did not appear with the dense fixture; cannot drive the scenario."
            )
        }

        // Phase 1: Today idle — 24 active timers tick at 1 Hz plus minute
        // clocks (heatmap, weekly gross, overview) run here.
        phase("today-idle", duration: 15) {
            RunLoop.current.run(until: Date().addingTimeInterval(15))
        }

        // Phase 2: Today scroll — dense timeline (600 entries) + heatmaps.
        phase("today-scroll", duration: 20) {
            for _ in 0 ..< 8 {
                measureSwipe("today-scroll") {
                    app.swipeUp(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }
            for _ in 0 ..< 8 {
                measureSwipe("today-scroll") {
                    app.swipeDown(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.4))
            }
        }

        // Phase 3: Tasks — 1,200-task tree.
        restoreTabBar(app)
        app.buttons["phone.tab.tasks"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["tasks.view"].waitForExistence(timeout: 15))
        phase("tasks-scroll", duration: 20) {
            for _ in 0 ..< 12 {
                measureSwipe("tasks-scroll") {
                    app.swipeUp(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
            for _ in 0 ..< 4 {
                measureSwipe("tasks-scroll") {
                    app.swipeDown(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
        }

        // Phase 4: Inbox — 400 items.
        restoreTabBar(app)
        app.buttons["phone.tab.inbox"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["inbox.view"].waitForExistence(timeout: 15))
        phase("inbox-scroll", duration: 15) {
            for _ in 0 ..< 10 {
                measureSwipe("inbox-scroll") {
                    app.swipeUp(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
        }

        // Phase 5: Analytics — dense multi-day ledger.
        restoreTabBar(app)
        app.buttons["phone.tab.analytics"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["analytics.view"].waitForExistence(timeout: 15))
        phase("analytics-scroll", duration: 15) {
            for _ in 0 ..< 10 {
                measureSwipe("analytics-scroll") {
                    app.swipeUp(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
        }

        // Phase 6: Return to Today — final idle to catch steady-state clocks.
        restoreTabBar(app)
        app.buttons["phone.tab.today"].firstMatch.tap()
        XCTAssertTrue(app.descendants(matching: .any)["home.view"].waitForExistence(timeout: 15))
        phase("today-idle-final", duration: 10) {
            RunLoop.current.run(until: Date().addingTimeInterval(10))
        }
    }

    /// `.tabBarMinimizeBehavior(.onScrollDown)` collapses the tab bar after
    /// downward scrolling; scroll back up before tapping a tab.
    private func restoreTabBar(_ app: XCUIApplication) {
        for _ in 0 ..< 2 {
            app.swipeDown(velocity: .fast)
            RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    }

    /// Marks a named window in the marker file and runs the interaction.
    private func phase(
        _ name: String,
        duration: TimeInterval,
        interaction: () -> Void
    ) {
        let start = Date().timeIntervalSince1970
        interaction()
        let end = Date().timeIntervalSince1970
        let entry: [String: Any] = [
            "phase": name,
            "start": start,
            "end": end,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: entry),
           let line = String(data: data, encoding: .utf8)
        {
            if FileManager.default.fileExists(atPath: markerFile.path) == false {
                FileManager.default.createFile(
                    atPath: markerFile.path,
                    contents: nil
                )
            }
            if let handle = FileHandle(forWritingAtPath: markerFile.path) {
                handle.seekToEndOfFile()
                handle.write((line + "\n").data(using: .utf8)!)
                try? handle.close()
            }
        }
        print("PERF-PHASE \(name) start=\(start) end=\(end)")
    }

    private func measureSwipe(
        _ phaseName: String,
        gesture: () -> Void
    ) {
        let start = Date()
        gesture()
        let elapsed = Date().timeIntervalSince(start)
        swipeDurations[phaseName, default: []].append(elapsed)
    }

    private func dumpAXTree(
        _ app: XCUIApplication,
        to path: String
    ) {
        let tree = app.debugDescription
        try? tree.write(
            toFile: path,
            atomically: true,
            encoding: .utf8
        )
        print(
            "PERF-AX-TREE \(path) bytes=\(tree.utf8.count) "
                + "prefix=\(tree.prefix(300))"
        )
    }
}
