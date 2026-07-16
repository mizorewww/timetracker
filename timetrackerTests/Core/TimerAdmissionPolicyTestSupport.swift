import Foundation
@testable import timetracker

nonisolated enum TimerAdmissionPolicyFixtures {
    static func snapshot(
        segmentID: Int,
        taskID: Int,
        sessionID: Int? = nil,
        startedAt: TimeInterval
    ) -> TimerActiveSegmentSnapshot {
        TimerActiveSegmentSnapshot(
            segmentID: uuid(segmentID),
            sessionID: uuid(sessionID ?? segmentID + 1_000),
            taskID: uuid(taskID),
            startedAt: Date(timeIntervalSinceReferenceDate: startedAt)
        )
    }

    static func uuid(_ value: Int) -> UUID {
        let digits = String(value, radix: 16)
        precondition(digits.count <= 12)
        let tail = String(repeating: "0", count: 12 - digits.count) + digits
        guard let id = UUID(uuidString: "00000000-0000-0000-0000-\(tail)") else {
            preconditionFailure("Unable to create a deterministic test UUID")
        }
        return id
    }
}
