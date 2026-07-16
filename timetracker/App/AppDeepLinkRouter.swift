import Foundation

enum AppDeepLinkAction: Equatable {
    case open(TimeTrackerStore.DesktopDestination)
    case startTimerPicker
    case startTimer(UUID)
    case stopTimer(AppDeepLinkStopTarget?)
    case newTask
    case openTask(UUID)
}

enum AppDeepLinkStopTarget: Equatable {
    case segment(UUID)
    case task(UUID)
}

struct AppDeepLinkRouter {
    static let maximumURLBytes = 2_048

    func action(for url: URL) -> AppDeepLinkAction? {
        guard url.absoluteString.utf8.count <= Self.maximumURLBytes,
              url.scheme?.lowercased() == "timetracker",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.fragment == nil else {
            return nil
        }

        let path = url.pathComponents.filter { $0 != "/" }
        guard let host = url.host?.lowercased() else { return nil }

        switch host {
        case "open":
            guard path.count == 1, let rawDestination = path.first else { return nil }
            guard hasNoQueryItems(url) else { return nil }
            guard let destination = destination(for: rawDestination) else { return nil }
            return .open(destination)
        case "timer":
            guard path.count == 1, let operation = path.first else { return nil }
            let parameter = timerParameter(from: url)
            switch (operation, parameter) {
            case ("start", .absent):
                return .startTimerPicker
            case ("start", .task(let taskID)):
                return .startTimer(taskID)
            case ("stop", .absent):
                return .stopTimer(nil)
            case ("stop", .task(let taskID)):
                return .stopTimer(.task(taskID))
            case ("stop", .segment(let segmentID)):
                return .stopTimer(.segment(segmentID))
            default:
                return nil
            }
        case "task":
            guard path.count == 1, let taskRoute = path.first else { return nil }
            guard hasNoQueryItems(url) else { return nil }
            if taskRoute == "new" { return .newTask }
            guard let taskID = UUID(uuidString: taskRoute) else { return nil }
            return .openTask(taskID)
        default:
            return nil
        }
    }

    private func destination(for rawValue: String) -> TimeTrackerStore.DesktopDestination? {
        switch rawValue.lowercased() {
        case "today", "home":
            return .today
        case "inbox":
            return .inbox
        case "tasks":
            return .tasks
        case "pomodoro":
            return .pomodoro
        case "analytics":
            return .analytics
        case "settings":
            return .settings
        default:
            return nil
        }
    }

    private func hasNoQueryItems(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.isEmpty ?? true
    }

    private func timerParameter(from url: URL) -> TimerParameter {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .invalid
        }
        let queryItems = components.queryItems ?? []
        guard queryItems.count <= 1 else { return .invalid }
        guard let item = queryItems.first else { return .absent }
        guard let rawValue = item.value,
              let id = UUID(uuidString: rawValue) else {
            return .invalid
        }
        switch item.name {
        case "taskID":
            return .task(id)
        case "segmentID":
            return .segment(id)
        default:
            return .invalid
        }
    }
}

private enum TimerParameter {
    case absent
    case task(UUID)
    case segment(UUID)
    case invalid
}

/// A small, scene-local buffer for URLs received before SwiftData is ready.
///
/// Entries are deduplicated by semantic action, oldest-first capped, and only
/// accepted after the same strict validation used for immediate routing.
struct PendingDeepLinkQueue {
    static let defaultCapacity = 16

    private(set) var urls: [URL] = []
    let capacity: Int

    init(capacity: Int = Self.defaultCapacity) {
        self.capacity = max(1, capacity)
    }

    @discardableResult
    mutating func enqueue(
        _ url: URL,
        router: AppDeepLinkRouter = AppDeepLinkRouter()
    ) -> Bool {
        guard let action = router.action(for: url) else { return false }

        urls.removeAll { router.action(for: $0) == action }
        if urls.count == capacity {
            urls.removeFirst()
        }
        urls.append(url)
        return true
    }

    mutating func drain() -> [URL] {
        let pendingURLs = urls
        urls.removeAll(keepingCapacity: true)
        return pendingURLs
    }

    mutating func removeAll() {
        urls.removeAll(keepingCapacity: false)
    }
}
