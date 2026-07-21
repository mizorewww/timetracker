import Foundation
import Testing
@testable import timetracker

struct TaskQuantityEntryEditorModelTests {
    @Test
    func addRouteCapturesGoalBaselineAndStableEntryIdentity() {
        let routeID = UUID()
        let entryID = UUID()
        let now = Date(timeIntervalSinceReferenceDate: 1_000)
        let detail = detail(total: 20, target: 50)

        let route = TaskQuantityEntryEditorRoute.add(
            detail: detail,
            now: now,
            routeID: routeID,
            entryID: entryID
        )

        #expect(route.id == routeID)
        #expect(route.taskID == detail.progress.taskID)
        #expect(route.goalBaseline == detail.progress.goalBaseline)
        #expect(route.initialDraft.amount == 30)
        #expect(route.initialDraft.recordedAt == now)
        #expect(route.mode == .add(entryID: entryID))
    }

    @Test
    func completedGoalDefaultsNewProgressToOne() {
        let route = TaskQuantityEntryEditorRoute.add(
            detail: detail(total: 60, target: 50)
        )

        #expect(route.initialDraft.amount == 1)
    }

    @Test
    func editRouteKeepsEntryAndOperationBaselinesStable() {
        let detail = detail(total: 20, target: 50)
        let entryBaseline = TaskQuantityEntryMutationBaseline(
            entryID: UUID(),
            taskID: detail.progress.taskID,
            quantityGoalID: detail.progress.goalBaseline.goalID,
            clientMutationID: UUID()
        )
        let entry = TaskQuantityEntrySnapshot(
            id: entryBaseline.entryID,
            baseline: entryBaseline,
            amount: 20,
            recordedAt: Date(timeIntervalSinceReferenceDate: 2_000)
        )
        let updateID = UUID()
        let deleteID = UUID()

        let route = TaskQuantityEntryEditorRoute.edit(
            detail: detail,
            entry: entry,
            updateOperationID: updateID,
            deleteOperationID: deleteID
        )

        #expect(route.initialDraft.amount == 20)
        #expect(route.initialDraft.recordedAt == entry.recordedAt)
        #expect(
            route.mode == .edit(
                entryBaseline: entryBaseline,
                updateOperationID: updateID,
                deleteOperationID: deleteID
            )
        )
    }

    @Test
    func editorDraftUsesPersistenceAmountAndDateBounds() {
        #expect(
            TaskQuantityEntryEditorDraft(
                amount: 1,
                recordedAt: PersistentDatePolicy.minimumDate
            ).isValid
        )
        #expect(
            TaskQuantityEntryEditorDraft(
                amount: 0,
                recordedAt: PersistentDatePolicy.minimumDate
            ).isValid == false
        )
        #expect(
            TaskQuantityEntryEditorDraft(
                amount: 1_000_001,
                recordedAt: PersistentDatePolicy.minimumDate
            ).isValid == false
        )
        #expect(
            TaskQuantityEntryEditorDraft(
                amount: 1,
                recordedAt: PersistentDatePolicy.maximumDateExclusive
            ).isValid == false
        )
    }

    private func detail(
        total: Int64,
        target: Int64
    ) -> TaskQuantityDetailSnapshot {
        let taskID = UUID()
        return TaskQuantityDetailSnapshot(
            progress: TaskQuantityProgressSnapshot(
                taskID: taskID,
                goalBaseline: TaskQuantityGoalMutationBaseline(
                    goalID: TaskProgressIdentity.quantityGoalID(
                        taskID: taskID
                    ),
                    taskID: taskID,
                    clientMutationID: UUID()
                ),
                targetAmount: target,
                unitLabel: "reps",
                totalAmount: total,
                entryCount: 0,
                entryRevision: UUID(),
                isRecordingAllowed: true
            ),
            entries: [],
            recurrenceRole: .ordinary
        )
    }
}
