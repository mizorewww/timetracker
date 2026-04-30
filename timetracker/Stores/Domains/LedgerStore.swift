import Foundation

struct LedgerStore {
    private(set) var activeSegments: [TimeSegment] = []
    private(set) var pausedSessions: [TimeSession] = []
    private(set) var todaySegments: [TimeSegment] = []
    private(set) var allSegments: [TimeSegment] = []
    private(set) var sessions: [TimeSession] = []

    mutating func refresh(repository: TimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        try refreshVisible(repository: repository, now: now, calendar: calendar)
        try refreshHistory(repository: repository)
    }

    mutating func refreshVisible(repository: TimeTrackingRepository, now: Date = Date(), calendar: Calendar = .current) throws {
        activeSegments = try repository.activeSegments()
        pausedSessions = try repository.pausedSessions()

        let today = calendar.dateInterval(of: .day, for: now) ?? DateInterval(start: now, duration: 24 * 60 * 60)
        todaySegments = try repository.segments(from: today.start, to: today.end, now: now)
        mergeVisibleSegments(todayInterval: today, now: now)
    }

    mutating func refreshHistory(repository: TimeTrackingRepository) throws {
        allSegments = try repository.allSegments()
        sessions = try repository.sessions()
    }

    private mutating func mergeVisibleSegments(todayInterval: DateInterval, now: Date) {
        guard !allSegments.isEmpty else {
            allSegments = todaySegments
            return
        }

        let visibleIDs = Set(todaySegments.map(\.id))
        allSegments = allSegments
            .filter { segment in
                if visibleIDs.contains(segment.id) {
                    return false
                }
                let end = segment.endedAt ?? now
                return !(segment.startedAt < todayInterval.end && end > todayInterval.start)
            } + todaySegments
        allSegments.sort { $0.startedAt < $1.startedAt }
    }
}
