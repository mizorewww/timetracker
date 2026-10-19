import Foundation

extension TimeTrackerStore {
    func completedFocusRoundSegments(
        segmentIDs: [UUID]
    ) -> [TimeSegment] {
        segmentIDs.compactMap { segmentID in
            guard let segment = ledgerDomainStore.segment(for: segmentID),
                  segment.deletedAt == nil
            else {
                return nil
            }
            return segment
        }
    }
}
