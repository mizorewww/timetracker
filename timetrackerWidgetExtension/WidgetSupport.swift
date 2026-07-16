import AppIntents
import Foundation
import SwiftUI

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum WidgetDeepLinks {
    static let today = URL(string: "timetracker://open/today")!

    static func startTimer(taskID: UUID) -> URL {
        URL(string: "timetracker://timer/start?taskID=\(taskID.uuidString)")!
    }

    static func stopTimer(segmentID: String) -> URL {
        URL(string: "timetracker://timer/stop?segmentID=\(segmentID)")!
    }
}

struct WidgetStopTimerIntent: AppIntent {
    static var title: LocalizedStringResource = "Stop Timer"
    static var description = IntentDescription("Stop this running Time Tracker timer.")
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

enum WidgetElapsedFormatter {
    nonisolated static func clock(_ seconds: Int) -> String {
        let safeSeconds = max(0, seconds)
        let pattern: Duration.TimeFormatStyle.Pattern = safeSeconds >= 3_600
            ? .hourMinuteSecond
            : .minuteSecond
        return Duration.seconds(safeSeconds).formatted(
            .time(pattern: pattern).locale(.autoupdatingCurrent)
        )
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
