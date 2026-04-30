import Foundation
import SwiftData

@Model
final class DailySummary {
    var id: UUID = UUID()
    var date: Date = Date()
    var taskID: UUID?
    var grossSeconds: Int = 0
    var wallClockSeconds: Int = 0
    var pomodoroCount: Int = 0
    var interruptionCount: Int = 0
    var generatedAt: Date = Date()
    var version: Int = 1

    init(date: Date, taskID: UUID?, grossSeconds: Int, wallClockSeconds: Int, pomodoroCount: Int, interruptionCount: Int, version: Int = 1) {
        self.id = UUID()
        self.date = date
        self.taskID = taskID
        self.grossSeconds = grossSeconds
        self.wallClockSeconds = wallClockSeconds
        self.pomodoroCount = pomodoroCount
        self.interruptionCount = interruptionCount
        self.generatedAt = Date()
        self.version = version
    }
}
