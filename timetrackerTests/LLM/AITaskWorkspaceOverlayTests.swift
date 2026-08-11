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
    func snapshotFingerprintRoundTripsAndRejectsTampering() throws {
        let snapshot = AITaskWorkspaceSnapshot(
            categories: [],
            tasks: [],
            checklistItems: []
        )
        let encoder = JSONEncoder()
        let encoded = try encoder.encode(snapshot)

        #expect(try JSONDecoder().decode(AITaskWorkspaceSnapshot.self, from: encoded) == snapshot)

        var json = try #require(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        json["contextFingerprint"] = "tampered"
        let tampered = try JSONSerialization.data(withJSONObject: json)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(AITaskWorkspaceSnapshot.self, from: tampered)
        }
    }
}
