import AppIntents
import Foundation

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum WidgetDeepLinks {
    static let today = URL(string: "timetracker://open/today")!

    static func startTimer(taskID: UUID) -> URL {
        URL(
            string: "timetracker://timer/start?taskID=\(taskID.uuidString)&source=widget"
        )!
    }

    nonisolated static func stopTimer(segmentID: String) -> URL {
        URL(string: "timetracker://timer/stop?segmentID=\(segmentID)")!
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
