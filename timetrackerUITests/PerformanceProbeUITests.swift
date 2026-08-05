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

    func testDenseTodayScrollAndPageTraversal() throws {
        let app = launchApp()

        let ready = app.otherElements["app.initialConfiguration.ready"]
        XCTAssertTrue(
            ready.waitForExistence(timeout: 240),
            "The app never finished initial configuration with the dense fixture."
        )
        try XCTSkipIf(
            app.otherElements["home.view"].waitForExistence(timeout: 10) == false,
            "Today did not appear; cannot drive the dense scenario."
        )

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
        app.buttons["phone.tab.tasks"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["tasks.view"].waitForExistence(timeout: 15))
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
        app.buttons["phone.tab.inbox"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["inbox.view"].waitForExistence(timeout: 15))
        phase("inbox-scroll", duration: 15) {
            for _ in 0 ..< 10 {
                measureSwipe("inbox-scroll") {
                    app.swipeUp(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
        }

        // Phase 5: Analytics — dense multi-day ledger.
        app.buttons["phone.tab.analytics"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["analytics.view"].waitForExistence(timeout: 15))
        phase("analytics-scroll", duration: 15) {
            for _ in 0 ..< 10 {
                measureSwipe("analytics-scroll") {
                    app.swipeUp(velocity: .fast)
                }
                RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            }
        }

        // Phase 6: Return to Today — final idle to catch steady-state clocks.
        app.buttons["phone.tab.today"].firstMatch.tap()
        XCTAssertTrue(app.otherElements["home.view"].waitForExistence(timeout: 15))
        phase("today-idle-final", duration: 10) {
            RunLoop.current.run(until: Date().addingTimeInterval(10))
        }
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
        let entry = [
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
}
