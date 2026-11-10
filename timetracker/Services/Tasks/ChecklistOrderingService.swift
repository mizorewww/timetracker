import Foundation
import SwiftUI

struct ChecklistOrderingElement<ID: Hashable>: Equatable {
    let id: ID
    let isCompleted: Bool
}

enum ChecklistOrderingService {
    static func completionGrouped<Element>(
        _ elements: [Element],
        isCompleted: (Element) -> Bool
    ) -> [Element] {
        var incomplete: [Element] = []
        var completed: [Element] = []
        incomplete.reserveCapacity(elements.count)
        completed.reserveCapacity(elements.count)

        for element in elements {
            if isCompleted(element) {
                completed.append(element)
            } else {
                incomplete.append(element)
            }
        }
        return incomplete + completed
    }

    static func reorderedIDs<ID: Hashable>(
        elements: [ChecklistOrderingElement<ID>],
        sourceOffsets: IndexSet,
        destination: Int
    ) -> [ID]? {
        guard !sourceOffsets.isEmpty else {
            return elements.map(\.id)
        }
        guard sourceOffsets.allSatisfy({ elements.indices.contains($0) }) else {
            return nil
        }

        let sourceStates = Set(sourceOffsets.map { elements[$0].isCompleted })
        guard sourceStates.count == 1, let sourceState = sourceStates.first else {
            return nil
        }

        let groupIndices = elements.indices.filter { elements[$0].isCompleted == sourceState }
        guard let groupStart = groupIndices.first,
              let groupEnd = groupIndices.last,
              destination >= groupStart,
              destination <= groupEnd + 1
        else {
            return nil
        }

        var ids = elements.map(\.id)
        ids.move(fromOffsets: sourceOffsets, toOffset: destination)
        return ids
    }

    static func canMove<ID: Hashable>(
        elements: [ChecklistOrderingElement<ID>],
        sourceOffsets: IndexSet,
        destination: Int
    ) -> Bool {
        reorderedIDs(elements: elements, sourceOffsets: sourceOffsets, destination: destination) != nil
    }
}
