#if DEBUG
import Foundation

extension TimeTrackerStore {
    @discardableResult
    func applyFirstHealthTimelineFixtureIfRequested(
        arguments: [String] = CommandLine.arguments,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> Bool {
        guard AppRuntimeEnvironment.isTestHost,
              arguments.contains("--uitesting-first-health-timeline")
        else {
            return false
        }

        let startOfDay = calendar.startOfDay(for: now)
        let interval = DateInterval(
            start: startOfDay.addingTimeInterval(16 * 60 * 60),
            duration: 45 * 60
        )
        isAppleHealthTimelineEnabled = true
        appleHealthTimelineItems = [
            AppleHealthTimelineItem(
                id: .appleHealthWorkout(
                    UUID(
                        uuidString:
                        "D0700000-0000-4000-8000-000000000001"
                    )!
                ),
                subject: .appleHealthWorkout(.running),
                interval: interval
            ),
        ]
        appleHealthTimelineState = .content(
            interval: DateInterval(
                start: startOfDay,
                duration: 24 * 60 * 60
            ),
            refreshedAt: now,
            itemCount: 1
        )
        return true
    }

    func applyLiveLLMConfigurationIfRequested(
        arguments: [String] = CommandLine.arguments,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) {
        #if os(iOS) && targetEnvironment(simulator)
        guard arguments.contains("--uitesting"),
              arguments.contains("--uitesting-live-llm"),
              let endpoint = environment[
                  "TIMETRACKER_UI_TEST_LIVE_LLM_ENDPOINT"
              ],
              let apiKey = environment[
                  "TIMETRACKER_UI_TEST_LIVE_LLM_API_KEY"
              ],
              let modelID = environment[
                  "TIMETRACKER_UI_TEST_LIVE_LLM_MODEL"
              ]
        else {
            return
        }

        _ = setLLMConfiguration(
            endpoint: endpoint,
            apiKey: apiKey,
            selectedModel: modelID,
            availableModelIDs: [modelID],
            reasoningEffort: .max
        )
        #endif
    }

    /// Drives the app to a screen for screenshot audits.
    ///
    /// Test-host only. An environment variable is far easier to leak into an
    /// ordinary launch than a launch argument, and the `sync-conflict` route
    /// fabricates a prompt whose confirmation starts a real destructive cloud
    /// recovery. Both call sites are XCUITests, which always pass `--uitesting`.
    func applyUIAuditRouteIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard AppRuntimeEnvironment.isTestHost else { return }
        guard let rawRoute = environment["TIMETRACKER_UI_AUDIT_ROUTE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
            !rawRoute.isEmpty
        else {
            return
        }

        switch rawRoute {
        case "today", "home":
            closeTaskDetailNavigation()
            desktopDestination = .today
        case "inbox":
            closeTaskDetailNavigation()
            desktopDestination = .inbox
        case "tasks":
            closeTaskDetailNavigation()
            desktopDestination = .tasks
        case "focus", "pomodoro":
            closeTaskDetailNavigation()
            desktopDestination = .pomodoro
        case "analytics":
            closeTaskDetailNavigation()
            desktopDestination = .analytics
        case "settings":
            closeTaskDetailNavigation()
            desktopDestination = .settings
        case "sync-conflict":
            closeTaskDetailNavigation()
            desktopDestination = .today
            pendingSyncConflict = SyncConflictPrompt(
                id: UUID(),
                detectedAt: Date(),
                localSummary: "12 tasks · 24 time records",
                cloudSummary: "11 tasks · 22 time records"
            )
        case "task-detail":
            let requestedTitle = environment["TIMETRACKER_UI_AUDIT_TASK_TITLE"]
            if let task = tasks.first(where: { requestedTitle == nil || $0.title == requestedTitle }) {
                openTaskDetail(task.id)
            }
        default:
            break
        }
    }
}
#endif
