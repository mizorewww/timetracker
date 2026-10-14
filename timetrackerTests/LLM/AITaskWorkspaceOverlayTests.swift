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
}
