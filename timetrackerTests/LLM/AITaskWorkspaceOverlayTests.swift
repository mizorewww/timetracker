import Foundation
import Testing
@testable import timetracker

struct AITaskWorkspaceOverlayTests {
    @Test
    func unavailableIdentitiesReturnTypedErrors() {
        let categoryID = UUID()
        let taskID = UUID()
        let checklistItemID = UUID()
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(
                categories: [],
                tasks: [],
                checklistItems: []
            )
        )

        #expect(throws: AITaskWorkspaceOverlayError.categoryUnavailable(categoryID)) {
            try overlay.deleteCategory(id: categoryID)
        }
        #expect(throws: AITaskWorkspaceOverlayError.taskUnavailable(taskID)) {
            try overlay.deleteTask(id: taskID)
        }
        #expect(
            throws: AITaskWorkspaceOverlayError.checklistItemUnavailable(
                checklistItemID
            )
        ) {
            try overlay.deleteChecklistItem(id: checklistItemID)
        }
    }

    @Test
    func moveIntoOwnSubtreeIsACycleAndDeepMovesCountTheSubtree() throws {
        var overlay = AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(categories: [], tasks: [], checklistItems: [])
        )
        let chain = try (0 ... AITaskWorkspaceOverlay.maximumAncestorDepth).reduce(into: [UUID]()) { ids, _ in
            try ids.append(createTask(in: &overlay, parentID: ids.last))
        }
        let branch = try createTask(in: &overlay, parentID: nil)
        _ = try createTask(in: &overlay, parentID: branch)

        #expect(throws: AITaskWorkspaceOverlayError.depthExceeded) {
            try createTask(in: &overlay, parentID: chain.last)
        }
        #expect(throws: AITaskWorkspaceOverlayError.hierarchyCycle) {
            try move(chain[0], under: chain[2], in: &overlay)
        }
        // The branch is two levels tall, so it fits only one level short of
        // the deepest allowed parent.
        #expect(throws: AITaskWorkspaceOverlayError.depthExceeded) {
            try move(branch, under: chain[chain.count - 2], in: &overlay)
        }
        try move(branch, under: chain[chain.count - 3], in: &overlay)
        #expect(overlay.task(id: branch)?.parentID == chain[chain.count - 3])
    }

    @discardableResult
    private func createTask(in overlay: inout AITaskWorkspaceOverlay, parentID: UUID?) throws -> UUID {
        try overlay.createTask(
            id: UUID(),
            title: "Task",
            parentID: parentID,
            categoryID: nil,
            notes: "",
            estimatedMinutes: nil,
            dueAt: nil,
            iconName: #require(SymbolCatalog.symbolNameSet.first),
            colorHex: #require(TaskColorPalette.hexValues.first)
        ).id
    }

    private func move(_ id: UUID, under parentID: UUID, in overlay: inout AITaskWorkspaceOverlay) throws {
        let task = try #require(overlay.task(id: id))
        try overlay.updateTask(
            id: id,
            title: task.title,
            parentID: parentID,
            categoryID: nil,
            notes: task.notes,
            estimatedMinutes: task.estimatedMinutes,
            dueAt: task.dueAt,
            iconName: task.iconName,
            colorHex: task.colorHex
        )
    }
}
