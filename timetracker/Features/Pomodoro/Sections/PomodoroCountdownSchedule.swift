import SwiftUI

struct PomodoroCountdownSchedule: TimelineSchedule {
    let deadline: Date?

    nonisolated func entries(from startDate: Date, mode: Mode) -> AnySequence<Date> {
        Self.entries(
            from: startDate,
            through: deadline,
            interval: mode == .lowFrequency ? 60 : 1
        )
    }

    nonisolated static func entries(
        from startDate: Date,
        through deadline: Date?,
        interval: TimeInterval = 1
    ) -> AnySequence<Date> {
        let endDate = deadline.map { max(startDate, $0) } ?? startDate
        let step = max(0.1, interval)
        return AnySequence(
            sequence(first: startDate) { currentDate in
                guard currentDate < endDate else { return nil }
                return min(currentDate.addingTimeInterval(step), endDate)
            }
        )
    }
}
