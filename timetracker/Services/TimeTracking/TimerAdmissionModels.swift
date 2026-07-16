import Foundation

nonisolated struct TimerActiveSegmentSnapshot: Hashable, Sendable {
    let segmentID: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
}

nonisolated enum TimerAdmissionMode: Hashable, Sendable {
    case exclusive
    case parallel
}

nonisolated enum TimerSameTaskStartBehavior: Hashable, Sendable {
    case reuseOldest
    case replaceAll
}

nonisolated enum TimerStartDecision: Hashable, Sendable {
    case createNew
    case reuse(TimerActiveSegmentSnapshot)
}

nonisolated struct TimerStartPlan: Hashable, Sendable {
    let decision: TimerStartDecision
    let segmentsToStop: [TimerActiveSegmentSnapshot]
}

nonisolated enum TimerStopTarget: Hashable, Sendable {
    case segment(UUID)
    case task(UUID)
    case current
}

nonisolated struct TimerStopPlan: Hashable, Sendable {
    let segmentsToStop: [TimerActiveSegmentSnapshot]

    var isNoOp: Bool {
        segmentsToStop.isEmpty
    }
}
