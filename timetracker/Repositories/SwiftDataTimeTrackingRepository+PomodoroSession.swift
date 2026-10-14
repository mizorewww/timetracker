import Foundation
import SwiftData

/// Ledger writes that close a Pomodoro session at its business deadline rather
/// than the wall clock. Both the Pomodoro repository and general timer
/// commands (widget, Watch, deep link, ledger edit) go through these, so a
/// stop after a suspended deadline never records suspension as focus time.
extension SwiftDataTimeTrackingRepository {
    /// The end date for a focus phase that expired at `deadline`: never before
    /// the latest live segment start, so no segment gets a negative duration.
    func pomodoroPhaseEndDate(sessionID: UUID, deadline: Date) throws -> Date {
        let latestStart = try sessionSegments(sessionID)
            .filter { $0.deletedAt == nil }
            .map(\.startedAt)
            .max()
        return max(deadline, latestStart ?? deadline)
    }

    /// Clips every live segment that runs past `endedAt`, then closes the
    /// session at its latest segment end.
    func endPomodoroSession(_ sessionID: UUID, at endedAt: Date, mutationDate: Date) throws {
        let segments = try sessionSegments(sessionID).filter { $0.deletedAt == nil }
        for segment in segments where segment.endedAt.map({ $0 > endedAt }) ?? true {
            segment.endedAt = max(segment.startedAt, endedAt)
            segment.updatedAt = mutationDate
            segment.deviceID = deviceID
        }
        guard let session = try canonicalSessions(ids: [sessionID]).first,
              session.deletedAt == nil
        else {
            return
        }
        let latestEnd = segments.compactMap(\.endedAt).max() ?? endedAt
        session.endedAt = max(session.startedAt, latestEnd)
        session.markMutated(at: mutationDate, deviceID: deviceID)
    }

    /// Tombstones the session and all of its segments, closing open ones at
    /// `endedAt` first so the tombstoned rows keep a bounded range.
    func discardPomodoroSession(_ sessionID: UUID, endedAt: Date, mutationDate: Date) throws {
        let segments = try sessionSegments(sessionID)
        for segment in segments {
            segment.endedAt = max(segment.startedAt, segment.endedAt ?? endedAt)
            segment.deletedAt = mutationDate
            segment.updatedAt = mutationDate
            segment.deviceID = deviceID
        }
        guard let session = try canonicalSessions(ids: [sessionID]).first else { return }
        let latestSegmentEnd = segments.compactMap(\.endedAt).max() ?? endedAt
        session.endedAt = max(session.startedAt, session.endedAt ?? latestSegmentEnd)
        session.deletedAt = mutationDate
        session.markMutated(at: mutationDate, deviceID: deviceID)
    }

    func pomodoroSessionTrackedSeconds(_ sessionID: UUID, now: Date) throws -> Int {
        try sessionSegments(sessionID)
            .filter { $0.deletedAt == nil }
            .reduce(0) { total, segment in
                total + TrackedTimePolicy.elapsedSeconds(
                    startedAt: segment.startedAt,
                    endedAt: segment.endedAt,
                    now: now
                )
            }
    }
}
