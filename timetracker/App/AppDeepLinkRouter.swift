import Foundation

enum AppDeepLinkAction: Equatable {
    case open(TimeTrackerStore.DesktopDestination)
    case startTimerPicker
    case startTimer(UUID)
    case stopTimer(UUID?)
    case newTask
}

struct AppDeepLinkRouter {
    func action(for url: URL) -> AppDeepLinkAction? {
        guard url.scheme == "timetracker" else { return nil }

        let path = url.pathComponents.filter { $0 != "/" }
        switch (url.host, path.first) {
        case ("open", let rawDestination?):
            guard let destination = destination(for: rawDestination) else { return nil }
            return .open(destination)
        case ("timer", "start"):
            if let taskID = taskID(from: url) {
                return .startTimer(taskID)
            }
            return .startTimerPicker
        case ("timer", "stop"):
            return .stopTimer(taskID(from: url))
        case ("task", "new"):
            return .newTask
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

    private func taskID(from url: URL) -> UUID? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first(where: { $0.name == "taskID" })?
            .value
            .flatMap(UUID.init(uuidString:))
    }
}
