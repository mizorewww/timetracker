import Foundation

extension StoreScopedSegmentCommandCoordinator {
    func outcome(
        subjectSegmentID: UUID,
        before: (
            segments: [UUID: LedgerSegmentMutationSnapshot],
            runs: [UUID: SegmentPomodoroMutationSnapshot]
        ),
        referenceDate: Date,
        timeRepository: SwiftDataTimeTrackingRepository,
        pomodoroRepository: SwiftDataPomodoroRepository
    ) throws -> StoreScopedSegmentMutationOutcome {
        let segmentsAfter = Dictionary(uniqueKeysWithValues: try timeRepository.segments(
            ids: Set(before.segments.keys)
        ).map {
            ($0.id, LedgerSegmentMutationSnapshot(segment: $0))
        })
        let runsAfter = Dictionary(uniqueKeysWithValues: try pomodoroRepository.runs(
            ids: Set(before.runs.keys)
        ).map {
            ($0.id, SegmentPomodoroMutationSnapshot(run: $0))
        })
        var segmentChanges = before.segments.compactMap { segmentID, snapshot in
            let after = segmentsAfter[segmentID]
            return after == snapshot ? nil : LedgerSegmentMutationChange(
                before: snapshot,
                after: after
            )
        }
        if segmentChanges.isEmpty,
           let subject = before.segments[subjectSegmentID] {
            segmentChanges = [
                LedgerSegmentMutationChange(
                    before: subject,
                    after: segmentsAfter[subjectSegmentID]
                ),
            ]
        }
        let pomodoroChanges = before.runs.compactMap { runID, snapshot in
            let after = runsAfter[runID]
            return after == snapshot ? nil : SegmentPomodoroMutationChange(
                before: snapshot,
                after: after
            )
        }
        return StoreScopedSegmentMutationOutcome(
            subjectSegmentID: subjectSegmentID,
            segmentChanges: segmentChanges.sorted {
                $0.before.segmentID.uuidString < $1.before.segmentID.uuidString
            },
            pomodoroChanges: pomodoroChanges.sorted {
                $0.before.runID.uuidString < $1.before.runID.uuidString
            },
            referenceDate: referenceDate
        )
    }
}
