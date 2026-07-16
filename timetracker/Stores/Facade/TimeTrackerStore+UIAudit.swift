#if DEBUG
import Foundation

extension TimeTrackerStore {
    func applyUIAuditRouteIfRequested(environment: [String: String] = ProcessInfo.processInfo.environment) {
        guard let rawRoute = environment["TIMETRACKER_UI_AUDIT_ROUTE"]?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased(),
              !rawRoute.isEmpty else {
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
