import Foundation

/// Immutable value captured from a SwiftData model before a command mutates it.
/// Model instances are reference types, so retaining only `TimeSegment` objects
/// cannot produce a reliable before/after delta after an in-context edit.
struct LedgerSegmentSnapshot: Equatable {
    let id: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?

    init(_ segment: TimeSegment) {
        id = segment.id
        sessionID = segment.sessionID
        taskID = segment.taskID
        startedAt = segment.startedAt
        endedAt = segment.endedAt
    }

    func elapsedSeconds(at now: Date) -> Int {
        max(0, Int((endedAt ?? now).timeIntervalSince(startedAt)))
    }

    func overlaps(_ interval: DateInterval, at now: Date) -> Bool {
        let end = endedAt ?? now
        return startedAt < interval.end && end > interval.start
    }
}

struct LedgerSegmentChange: Equatable {
    let id: UUID
    let before: LedgerSegmentSnapshot?
    let after: LedgerSegmentSnapshot?
}
