import Foundation

enum AppDeepLinkAction: Equatable {
    case open(TimeTrackerStore.DesktopDestination)
    case startTimerPicker
    case startTimer(UUID)
    case stopTimer(UUID?)
    case newTask
    case openTask(UUID)
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
            switch (operation, taskIDParameter(from: url)) {
            case ("start", .absent):
                return .startTimerPicker
            case ("start", .value(let taskID)):
                return .startTimer(taskID)
            case ("stop", .absent):
                return .stopTimer(nil)
            case ("stop", .value(let taskID)):
                return .stopTimer(taskID)
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

    private func taskIDParameter(from url: URL) -> TaskIDParameter {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .invalid
        }
        let queryItems = components.queryItems ?? []
        guard queryItems.allSatisfy({ $0.name == "taskID" }), queryItems.count <= 1 else {
            return .invalid
        }
        guard let item = queryItems.first else { return .absent }
        guard let rawValue = item.value,
              let taskID = UUID(uuidString: rawValue) else {
            return .invalid
        }
        return .value(taskID)
    }
}

private enum TaskIDParameter {
    case absent
    case value(UUID)
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
