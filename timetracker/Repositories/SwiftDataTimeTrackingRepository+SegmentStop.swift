import Foundation

extension SwiftDataTimeTrackingRepository {
    func stopSegment(segmentID: UUID) throws {
        guard let segment = try canonicalSegments(ids: [segmentID]).first,
              segment.endedAt == nil
        else {
            return
        }
        let now = nowProvider()
        let endedAt = max(now, segment.startedAt)
        let linkedSession = try canonicalSessions(
            ids: [segment.sessionID]
        ).first
        let mutationDate = PersistentLWWMutationDate.strictlyDominating(
            preferred: now,
            observed: [segment.updatedAt] +
                [linkedSession?.updatedAt].compactMap { $0 }
        )
        try context.performAtomicMutation {
            segment.endedAt = endedAt
            segment.updatedAt = mutationDate
            segment.deviceID = deviceID

            guard let linkedSession else { return }
            let sessionSegments = try segments(
                sessionIDs: [linkedSession.id]
            )
            guard sessionSegments.contains(where: {
                $0.endedAt == nil
            }) == false else {
                return
            }
            linkedSession.endedAt = max(
                linkedSession.startedAt,
                sessionSegments.compactMap(\.endedAt).max() ?? endedAt
            )
            linkedSession.markMutated(
                at: mutationDate,
                deviceID: deviceID
            )
        }
    }
}
