import AppIntents
import Foundation

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum WidgetDeepLinks {
    nonisolated static func startTimer(taskID: UUID) -> URL {
        URL(
            string: "timetracker://timer/start?taskID=\(taskID.uuidString)&source=widget"
        )!
    }

    nonisolated static func stopTimer(segmentID: String) -> URL {
        URL(string: "timetracker://timer/stop?segmentID=\(segmentID)")!
    }
}

/// Small widgets ignore `Link` (the whole widget opens `widgetURL`), so the
/// start row is a button whose intent opens the start link.
struct WidgetStartTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "widget.action.start"
    static var description = IntentDescription("widget.intent.start.description")
    static var openAppWhenRun = false

    @Parameter(title: "widget.intent.parameter.task")
    var taskID: String

    init() {}

    init(taskID: UUID) {
        self.taskID = taskID.uuidString
    }

    func perform() async throws -> some IntentResult {
        guard let taskID = UUID(uuidString: taskID) else {
            return .result(opensIntent: OpenURLIntent(SystemSurfaceDeepLinks.today))
        }
        return .result(opensIntent: OpenURLIntent(WidgetDeepLinks.startTimer(taskID: taskID)))
    }
}

struct WidgetStopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Time Tracker to Stop"
    static var description = IntentDescription(
        "Open Time Tracker to stop this specific running timer."
    )
    static var openAppWhenRun = false

    @Parameter(title: "Timer")
    var segmentID: String

    init() {}

    init(segmentID: UUID) {
        self.segmentID = segmentID.uuidString
    }

    func perform() async throws -> some IntentResult {
        .result(opensIntent: OpenURLIntent(WidgetDeepLinks.stopTimer(segmentID: segmentID)))
    }
}
