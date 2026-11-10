import Foundation
import SwiftUI

enum OrderedTaskIDSelectionMutation {
    static func adding(_ id: UUID, to selectedIDs: [UUID]) -> [UUID] {
        guard selectedIDs.contains(id) == false else { return selectedIDs }
        return selectedIDs + [id]
    }

    static func removing(_ id: UUID, from selectedIDs: [UUID]) -> [UUID] {
        selectedIDs.filter { $0 != id }
    }

    static func toggling(_ id: UUID, in selectedIDs: [UUID]) -> [UUID] {
        selectedIDs.contains(id)
            ? removing(id, from: selectedIDs)
            : adding(id, to: selectedIDs)
    }

    static func removing(
        _ removedIDs: Set<UUID>,
        from selectedIDs: [UUID]
    ) -> [UUID] {
        guard removedIDs.isEmpty == false else { return selectedIDs }
        return selectedIDs.filter { removedIDs.contains($0) == false }
    }

    static func removingVisibleSelections(
        at offsets: IndexSet,
        visibleIDs: [UUID],
        from selectedIDs: [UUID]
    ) -> [UUID] {
        let removedIDs = Set(offsets.compactMap { offset in
            visibleIDs.indices.contains(offset) ? visibleIDs[offset] : nil
        })
        return removing(removedIDs, from: selectedIDs)
    }

    static func movingVisibleSelections(
        fromOffsets sourceOffsets: IndexSet,
        toOffset destination: Int,
        visibleIDs: [UUID],
        in selectedIDs: [UUID]
    ) -> [UUID] {
        guard sourceOffsets.isEmpty == false,
              destination >= 0,
              destination <= visibleIDs.count,
              sourceOffsets.allSatisfy(visibleIDs.indices.contains),
              Set(visibleIDs).count == visibleIDs.count,
              visibleIDs.allSatisfy({ visibleID in
                  selectedIDs.filter { $0 == visibleID }.count == 1
              })
        else {
            return selectedIDs
        }

        var reorderedVisibleIDs = visibleIDs
        reorderedVisibleIDs.move(fromOffsets: sourceOffsets, toOffset: destination)

        let visibleIDSet = Set(visibleIDs)
        var reorderedSelections = selectedIDs
        var reorderedVisibleIndex = 0
        for selectionIndex in reorderedSelections.indices
            where visibleIDSet.contains(reorderedSelections[selectionIndex])
        {
            reorderedSelections[selectionIndex] =
                reorderedVisibleIDs[reorderedVisibleIndex]
            reorderedVisibleIndex += 1
        }
        return reorderedVisibleIndex == reorderedVisibleIDs.count
            ? reorderedSelections
            : selectedIDs
    }
}
