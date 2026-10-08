import Foundation

extension TimeTrackerStore {
    func completedFocusRoundSegments(
        segmentIDs: [UUID]
    ) -> [TimeSegment] {
        if ledgerDomainStore.hasIndexedSegmentHistory {
            return segmentIDs.compactMap { segmentID in
                guard let segment = ledgerDomainStore.segment(for: segmentID),
                      segment.deletedAt == nil
                else {
                    return nil
                }
                return segment
            }
        }

        let fallbackByID = allSegments
            .visibleDeduplicatedByID()
            .reduce(into: [UUID: TimeSegment]()) { result, segment in
                result[segment.id] = segment
            }

        return segmentIDs.compactMap { segmentID in
            let segment = fallbackByID[segmentID]
            guard segment?.deletedAt == nil else { return nil }
            return segment
        }
    }
}
