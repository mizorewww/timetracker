import Foundation

enum AppDeepLinkAction: Equatable {
    case open(TimeTrackerStore.DesktopDestination)
    case openSettings
    case startTimerPicker
    case startTimer(UUID, source: TimeSessionSource)
    case stopTimer(AppDeepLinkStopTarget?)
    case newTask
    case openTask(UUID)
}

enum AppDeepLinkStopTarget: Equatable {
    case segment(UUID)
    case task(UUID)
}

struct AppDeepLinkRouter {
    static let maximumURLBytes = 2048

    func action(for url: URL) -> AppDeepLinkAction? {
        guard url.absoluteString.utf8.count <= Self.maximumURLBytes,
              url.scheme?.lowercased() == "timetracker",
              url.user == nil,
              url.password == nil,
              url.port == nil,
              url.fragment == nil
        else {
            return nil
        }

        let path = url.pathComponents.filter { $0 != "/" }
        guard let host = url.host?.lowercased() else { return nil }

        switch host {
        case "open":
            guard path.count == 1, let rawDestination = path.first, hasNoQueryItems(url) else { return nil }
            if rawDestination == "settings" {
                return .openSettings
            }
            return destination(for: rawDestination).map(AppDeepLinkAction.open)
        case "timer":
            guard path.count == 1, let operation = path.first else { return nil }
            switch operation {
            case "start":
                switch timerStartParameter(from: url) {
                case .absent:
                    return .startTimerPicker
                case let .task(taskID, source):
                    return .startTimer(taskID, source: source)
                case .invalid:
                    return nil
                }
            case "stop":
                switch timerStopParameter(from: url) {
                case .absent:
                    return .stopTimer(nil)
                case let .task(taskID):
                    return .stopTimer(.task(taskID))
                case let .segment(segmentID):
                    return .stopTimer(.segment(segmentID))
                case .invalid:
                    return nil
                }
            default:
                return nil
            }
        case "task":
            guard path.count == 1, let taskRoute = path.first, hasNoQueryItems(url) else { return nil }
            if taskRoute == "new" {
                return .newTask
            }
            guard let taskID = UUID(uuidString: taskRoute) else { return nil }
            return .openTask(taskID)
        default:
            return nil
        }
    }

    private func destination(for rawValue: String) -> TimeTrackerStore.DesktopDestination? {
        switch rawValue.lowercased() {
        case "today", "home":
            .today
        case "inbox":
            .inbox
        case "tasks":
            .tasks
        case "pomodoro":
            .pomodoro
        case "analytics":
            .analytics
        default:
            nil
        }
    }

    private func hasNoQueryItems(_ url: URL) -> Bool {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.isEmpty ?? true
    }

    private func timerStartParameter(from url: URL) -> TimerStartParameter {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .invalid
        }
        let queryItems = components.queryItems ?? []
        guard queryItems.isEmpty == false else { return .absent }
        guard queryItems.count == 1 || queryItems.count == 2 else { return .invalid }

        let taskItems = queryItems.filter { $0.name == "taskID" }
        guard taskItems.count == 1,
              let rawTaskID = taskItems[0].value,
              let taskID = UUID(uuidString: rawTaskID)
        else {
            return .invalid
        }
        if queryItems.count == 1 {
            return .task(taskID, source: .timer)
        }

        let sourceItems = queryItems.filter { $0.name == "source" }
        guard sourceItems.count == 1, sourceItems[0].value == "widget" else {
            return .invalid
        }
        return .task(taskID, source: .widget)
    }

    private func timerStopParameter(from url: URL) -> TimerStopParameter {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return .invalid
        }
        let queryItems = components.queryItems ?? []
        guard queryItems.count <= 1 else { return .invalid }
        guard let item = queryItems.first else { return .absent }
        guard let rawValue = item.value,
              let id = UUID(uuidString: rawValue)
        else {
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

private enum TimerStartParameter {
    case absent
    case task(UUID, source: TimeSessionSource)
    case invalid
}

private enum TimerStopParameter {
    case absent
    case task(UUID)
    case segment(UUID)
    case invalid
}

/// The one URL received before SwiftData (or the scene) could route it.
/// A newer link replaces an older one; only validated links are kept.
final class PendingDeepLink {
    private(set) var url: URL?

    @discardableResult
    func set(_ url: URL) -> Bool {
        guard AppDeepLinkRouter().action(for: url) != nil else { return false }
        self.url = url
        return true
    }

    func take() -> URL? {
        defer { url = nil }
        return url
    }

    /// Puts back a link that could not run yet, unless a newer one arrived.
    func restore(_ url: URL) {
        if self.url == nil {
            self.url = url
        }
    }

    func clear() {
        url = nil
    }
}
