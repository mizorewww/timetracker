import Foundation
import Testing
@testable import timetracker

@MainActor
struct CompletedPomodoroCountTests {
    @Test
    func countsOnlyRunsCompletedOnTheRequestedDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        let today = Date(timeIntervalSince1970: 1_800_000_000)
        let yesterday = today.addingTimeInterval(-86400)
        let store = makeTestStore()
        store.pomodoroRuns = [
            completedRun(endedAt: today),
            completedRun(endedAt: yesterday),
            completedRun(endedAt: today, deleted: true),
        ]

        #expect(store.completedPomodoroCount(on: today, calendar: calendar) == 1)
        #expect(store.completedPomodoroCount(on: yesterday, calendar: calendar) == 1)
    }

    private func completedRun(endedAt: Date, deleted: Bool = false) -> PomodoroRun {
        let run = PomodoroRun(taskID: UUID(), deviceID: "test")
        run.state = .completed
        run.endedAt = endedAt
        run.deletedAt = deleted ? endedAt : nil
        return run
    }
}
