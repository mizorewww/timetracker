import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreTaskEstimatePolicyTests {
    @Test
    func estimatePolicyNormalizesEmptyNegativeAndOversizedValues() {
        #expect(TaskEstimatePolicy.normalized(seconds: nil) == nil)
        #expect(TaskEstimatePolicy.normalized(seconds: 0) == nil)
        #expect(TaskEstimatePolicy.normalized(seconds: -1) == nil)
        #expect(TaskEstimatePolicy.normalized(seconds: 900) == 900)
        #expect(TaskEstimatePolicy.normalized(seconds: Int.max) == TaskEstimatePolicy.maximumSeconds)

        #expect(TaskEstimatePolicy.seconds(fromMinutes: nil) == nil)
        #expect(TaskEstimatePolicy.seconds(fromMinutes: -1) == nil)
        #expect(TaskEstimatePolicy.seconds(fromMinutes: 0) == nil)
        #expect(TaskEstimatePolicy.seconds(fromMinutes: 15) == 900)
        #expect(TaskEstimatePolicy.seconds(fromMinutes: Int.max) == TaskEstimatePolicy.maximumSeconds)
    }

    @Test @MainActor
    func repositoryEnforcesEstimateBoundsForNonEditorCallers() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(title: "Bounded", parentID: nil)

        try repository.updateTask(
            taskID: task.id,
            title: task.title,
            parentID: task.parentID,
            categoryID: nil,
            colorHex: task.colorHex,
            iconName: task.iconName,
            notes: task.notes,
            estimatedSeconds: Int.max,
            dueAt: task.dueAt
        )

        let restored = try #require(try repository.task(id: task.id))
        #expect(restored.estimatedSeconds == TaskEstimatePolicy.maximumSeconds)
    }
}
