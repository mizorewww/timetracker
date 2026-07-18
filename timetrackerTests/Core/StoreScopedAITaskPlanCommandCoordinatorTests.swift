import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedAITaskPlanCommandCoordinatorTests {
    @Test
    func createsCategoriesTopologicalTasksAssignmentsAndChecklists() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()

        let outcome = try coordinator(container: context.container).apply(fixture.draft)

        #expect(outcome.didCreate)
        #expect(outcome.createdCategoryIDs == [fixture.categoryID])
        #expect(outcome.createdTaskIDs == [fixture.childTaskID, fixture.rootTaskID])
        #expect(outcome.firstRootTaskID == fixture.rootTaskID)
        #expect(
            outcome.events == [
                .taskChanged(taskID: nil, affectedAncestorIDs: []),
                .checklistChanged(taskID: nil, affectedAncestorIDs: []),
            ]
        )

        let freshContext = ModelContext(context.container)
        let categories = try freshContext.fetch(FetchDescriptor<TaskCategory>())
        #expect(categories.map(\.id) == [fixture.categoryID])
        #expect(categories.first?.title == "Work")

        let tasks = try freshContext.fetch(FetchDescriptor<TaskNode>())
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let root = try #require(taskByID[fixture.rootTaskID])
        let child = try #require(taskByID[fixture.childTaskID])
        #expect(root.parentID == nil)
        #expect(root.notes == "Deliver this week")
        #expect(root.estimatedSeconds == 45 * 60)
        #expect(child.parentID == root.id)
        #expect(child.depth == root.depth + 1)
        #expect(child.path.isEmpty == false)

        let assignments = try freshContext.fetch(
            FetchDescriptor<TaskCategoryAssignment>()
        )
        #expect(assignments.count == 1)
        #expect(assignments.first?.taskID == root.id)
        #expect(assignments.first?.categoryID == fixture.categoryID)

        let checklistItems = try freshContext.fetch(FetchDescriptor<ChecklistItem>())
        #expect(checklistItems.count == 2)
        #expect(Set(checklistItems.map(\.taskID)) == [fixture.childTaskID])
        #expect(Set(checklistItems.map(\.title)) == ["Draft", "Review"])
        let checklistVisuals = try freshContext.fetch(
            FetchDescriptor<ChecklistItemVisual>()
        )
        #expect(checklistVisuals.count == 2)
        #expect(
            Set(checklistVisuals.map(\.checklistItemID)) ==
                Set(checklistItems.map(\.id))
        )
    }

    @Test
    func thrownStepRollsBackEveryCreatedFact() throws {
        enum InjectedFailure: Error {
            case stop
        }

        let context = try makeTestContext()
        let fixture = makePlanFixture()
        let coordinator = StoreScopedAITaskPlanCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-test",
            didReachCheckpoint: { checkpoint in
                guard case .taskCreated = checkpoint else { return }
                throw InjectedFailure.stop
            }
        )

        #expect(throws: InjectedFailure.self) {
            try coordinator.apply(fixture.draft)
        }

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<TaskCategory>()).isEmpty)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(
            try freshContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).isEmpty
        )
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
        #expect(
            try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>()).isEmpty
        )
    }

    @Test
    func replayOfTheSameDraftIsAnIdempotentSuccess() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()
        let coordinator = coordinator(container: context.container)

        let first = try coordinator.apply(fixture.draft)
        let second = try coordinator.apply(fixture.draft)

        #expect(first.didCreate)
        #expect(second.didCreate == false)
        #expect(second.createdCategoryIDs.isEmpty)
        #expect(second.createdTaskIDs.isEmpty)
        #expect(second.firstRootTaskID == fixture.rootTaskID)
        #expect(second.events.isEmpty)

        let freshContext = ModelContext(context.container)
        #expect(try freshContext.fetch(FetchDescriptor<TaskCategory>()).count == 1)
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).count == 2)
        #expect(
            try freshContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).count == 1
        )
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).count == 2)
        #expect(
            try freshContext.fetch(FetchDescriptor<ChecklistItemVisual>()).count == 2
        )
    }

    @Test
    func mixedPersistedIdentitiesRejectWithoutCompletingThePlan() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()
        _ = try SwiftDataTaskRepository(
            context: context,
            deviceID: "preexisting"
        ).createCategory(
            proposedID: fixture.categoryID,
            title: "Preexisting",
            colorHex: nil,
            iconName: nil,
            includesInForecast: true
        )

        #expect(throws: StoreScopedAITaskPlanMutationError.identityConflict) {
            try coordinator(container: context.container).apply(fixture.draft)
        }

        let freshContext = ModelContext(context.container)
        let categories = try freshContext.fetch(FetchDescriptor<TaskCategory>())
        #expect(categories.count == 1)
        #expect(categories.first?.title == "Preexisting")
        #expect(try freshContext.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(
            try freshContext.fetch(FetchDescriptor<TaskCategoryAssignment>()).isEmpty
        )
        #expect(try freshContext.fetch(FetchDescriptor<ChecklistItem>()).isEmpty)
    }

    @Test
    func applicationWriteGateRejectsBeforeCreatingAContextMutation() throws {
        let defaults = UserDefaults.standard
        let previousMode = defaults.object(forKey: AppCloudSync.modeKey)
        defaults.set(AppCloudSync.modeInMemoryFallback, forKey: AppCloudSync.modeKey)
        defer {
            if let previousMode {
                defaults.set(previousMode, forKey: AppCloudSync.modeKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.modeKey)
            }
        }

        let context = try makeTestContext()
        let fixture = makePlanFixture()
        #expect(throws: PersistenceWriteError.self) {
            try StoreScopedAITaskPlanCommandCoordinator(
                container: context.container,
                writeAuthorization: .applicationState,
                deviceID: "ai-test"
            ).apply(fixture.draft)
        }
        #expect(try context.fetch(FetchDescriptor<TaskCategory>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test
    func storeFacadeRefreshesSelectsFirstRootAndRoutesToTasks() throws {
        let context = try makeTestContext()
        let fixture = makePlanFixture()
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.desktopDestination = .today

        let result = store.saveAITaskPlan(fixture.draft)

        #expect(
            result == .saved(
                firstRootTaskID: fixture.rootTaskID,
                didCreate: true
            )
        )
        #expect(store.task(for: fixture.rootTaskID) != nil)
        #expect(store.task(for: fixture.childTaskID) != nil)
        #expect(store.selectedTaskID == fixture.rootTaskID)
        #expect(store.desktopDestination == .tasks)
        #expect(store.tasksRoute == nil)
        #expect(store.checklistItems(for: fixture.childTaskID).count == 2)
    }

    private struct PlanFixture {
        let draft: AITaskPlanDraft
        let categoryID: UUID
        let rootTaskID: UUID
        let childTaskID: UUID
    }

    private func makePlanFixture() -> PlanFixture {
        let categoryID = UUID()
        let rootTaskID = UUID()
        let childTaskID = UUID()
        return PlanFixture(
            draft: AITaskPlanDraft(
                categories: [
                    AITaskPlanCategoryDraft(
                        id: categoryID,
                        title: " Work ",
                        iconName: "briefcase.fill",
                        colorHex: "1677FF"
                    ),
                ],
                tasks: [
                    AITaskPlanTaskDraft(
                        id: childTaskID,
                        parentID: rootTaskID,
                        title: "Prepare release",
                        iconName: "hammer.fill",
                        colorHex: "6B5CFF",
                        checklistItems: [
                            AITaskPlanChecklistDraft(
                                title: "Draft",
                                iconName: "doc.text",
                                colorHex: "1677FF"
                            ),
                            AITaskPlanChecklistDraft(
                                title: "Review",
                                iconName: "eye.fill",
                                colorHex: "00A870"
                            ),
                        ]
                    ),
                    AITaskPlanTaskDraft(
                        id: rootTaskID,
                        categoryID: categoryID,
                        title: "Ship update",
                        notes: "Deliver this week",
                        estimatedMinutes: 45,
                        iconName: "shippingbox.fill",
                        colorHex: "FF8A00"
                    ),
                ],
                modelID: "test-model"
            ),
            categoryID: categoryID,
            rootTaskID: rootTaskID,
            childTaskID: childTaskID
        )
    }

    private func coordinator(
        container: ModelContainer
    ) -> StoreScopedAITaskPlanCommandCoordinator {
        StoreScopedAITaskPlanCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "ai-test"
        )
    }
}
