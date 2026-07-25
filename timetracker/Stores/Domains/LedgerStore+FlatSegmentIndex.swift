import Foundation

extension LedgerStore {
    mutating func updateFlatSegment(
        id: UUID,
        previousSnapshot: LedgerSegmentSnapshot?,
        model: TimeSegment?
    ) {
        if let existingIndex = segmentArrayIndexByID[id] {
            guard let model else {
                allSegments.remove(at: existingIndex)
                segmentArrayIndexByID.removeValue(forKey: id)
                reindexFlatSegments(from: existingIndex)
                return
            }

            if previousSnapshot?.startedAt == model.startedAt {
                // SwiftData returns the same reference after an in-context
                // edit. Avoid copying the shared flat-array buffer when its
                // model already exposes the new values.
                if allSegments[existingIndex] !== model {
                    allSegments[existingIndex] = model
                }
                return
            }

            allSegments.remove(at: existingIndex)
            segmentArrayIndexByID.removeValue(forKey: id)
            reindexFlatSegments(from: existingIndex)
        }

        guard let model else { return }
        let insertionIndex = allSegments.partitioningIndex { segmentStartOrder($0, model) }
        allSegments.insert(model, at: insertionIndex)
        reindexFlatSegments(from: insertionIndex)
    }

    mutating func reindexFlatSegments(from startIndex: Int) {
        guard startIndex < allSegments.count else { return }
        for index in startIndex ..< allSegments.count {
            segmentArrayIndexByID[allSegments[index].id] = index
        }
    }

    func segmentStartOrder(_ lhs: TimeSegment, _ rhs: TimeSegment) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt < rhs.startedAt
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}

private extension Array {
    func partitioningIndex(where belongsBefore: (Element) -> Bool) -> Int {
        var lowerBound = startIndex
        var upperBound = endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + distance(from: lowerBound, to: upperBound) / 2
            if belongsBefore(self[middle]) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }
}
