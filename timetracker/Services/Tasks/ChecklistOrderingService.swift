import Foundation

struct ChecklistOrderingElement<ID: Hashable>: Equatable {
    let id: ID
    let isCompleted: Bool
}

struct ChecklistOrderingService {
    func reorderedIDs<ID: Hashable>(
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
        guard let groupStart = groupIndices.first, let groupEnd = groupIndices.last else {
            return nil
        }
        guard destination >= groupStart, destination <= groupEnd + 1 else {
            return nil
        }

        return moved(elements.map(\.id), fromOffsets: sourceOffsets, toOffset: destination)
    }

    func canMove<ID: Hashable>(
        elements: [ChecklistOrderingElement<ID>],
        sourceOffsets: IndexSet,
        destination: Int
    ) -> Bool {
        reorderedIDs(elements: elements, sourceOffsets: sourceOffsets, destination: destination) != nil
    }

    private func moved<T>(_ values: [T], fromOffsets sourceOffsets: IndexSet, toOffset destination: Int) -> [T] {
        var copy = values
        let moving = sourceOffsets.sorted().map { copy[$0] }

        for offset in sourceOffsets.sorted(by: >) {
            copy.remove(at: offset)
        }

        let removedBeforeDestination = sourceOffsets.filter { $0 < destination }.count
        let insertionIndex = max(0, min(destination - removedBeforeDestination, copy.count))
        copy.insert(contentsOf: moving, at: insertionIndex)
        return copy
    }
}
