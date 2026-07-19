import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct StoreScopedAppleHealthTaskCatalogCommandCoordinatorTests {
    @Test
    func catalogUsesStableUniqueIdentitiesAndOnlyRequestedRoles() throws {
        let roles: Set<AppleHealthTaskRole> = [
            .sleep,
            .workout(.running),
            .workout(.walking),
        ]

        let plan = AppleHealthTaskCatalog.plan(for: roles)
        let reversed = AppleHealthTaskCatalog.plan(
            for: Set(roles.reversed())
        )
        let allIDs = plan.categories.map(\.id) +
            plan.tasks.map(\.id) +
            plan.tasks.map(\.categoryAssignmentID)

        #expect(plan == reversed)
        #expect(plan.categories.map(\.role) == [.exercise, .daily])
        #expect(plan.tasks.map(\.role) == [
            .workout(.walking),
            .workout(.running),
            .sleep,
        ])
        #expect(Set(allIDs).count == allIDs.count)
        #expect(
            AppleHealthTaskCatalog.taskDefinition(
                for: .workout(.running)
            ).id ==
                UUID(
                    uuidString: "A1200000-0000-4000-8000-000000000002"
                )
        )
        #expect(
            AppleHealthTaskCatalog.taskDefinition(for: .sleep).id ==
                UUID(
                    uuidString: "A1200000-0000-4000-8000-000000000012"
                )
        )
        #expect(
            plan.tasks.contains(where: {
                $0.role == .workout(.cycling)
            }) == false
        )
    }

    @Test
    func firstApplyCreatesOrdinaryDefinitionsReplayIsNoOpAndNewKindIsIncremental()
        throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        let firstRoles: Set<AppleHealthTaskRole> = [
            .workout(.running),
            .sleep,
        ]

        let first = try coordinator.apply(roles: firstRoles)
        let replay = try coordinator.apply(roles: firstRoles)
        let incremental = try coordinator.apply(
            roles: firstRoles.union([.workout(.cycling)])
        )

        #expect(first.createdCategoryIDs.count == 2)
        #expect(first.createdTaskIDs.count == 2)
        #expect(first.events == [
            .taskChanged(taskID: nil, affectedAncestorIDs: []),
        ])
        #expect(replay == .noChanges)
        #expect(incremental.createdCategoryIDs.isEmpty)
        #expect(incremental.createdTaskIDs == [
            AppleHealthTaskCatalog.taskDefinition(
                for: .workout(.cycling)
            ).id,
        ])

        let fresh = ModelContext(context.container)
        let categories = try fresh.fetch(FetchDescriptor<TaskCategory>())
        let tasks = try fresh.fetch(FetchDescriptor<TaskNode>())
        let assignments = try fresh.fetch(
            FetchDescriptor<TaskCategoryAssignment>()
        )
        #expect(categories.count == 2)
        #expect(tasks.count == 3)
        #expect(assignments.count == 3)
        #expect(categories.allSatisfy { $0.includesInForecast == false })
        #expect(tasks.allSatisfy {
            $0.createdAt == AppleHealthTaskCatalog.seedTimestamp &&
                $0.updatedAt == AppleHealthTaskCatalog.seedTimestamp &&
                $0.clientMutationID == $0.id &&
                $0.kindRaw == "task"
        })
        #expect(assignments.allSatisfy {
            $0.createdAt == AppleHealthTaskCatalog.seedTimestamp &&
                $0.updatedAt == AppleHealthTaskCatalog.seedTimestamp &&
                $0.clientMutationID == $0.id
        })
        #expect(try fresh.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try fresh.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test
    func replayPreservesUserRenameMoveAndArchive() throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        let role = AppleHealthTaskRole.workout(.running)
        let definition = AppleHealthTaskCatalog.taskDefinition(for: role)
        _ = try coordinator.apply(roles: [role])

        let editContext = ModelContext(context.container)
        let repository = SwiftDataTaskRepository(
            context: editContext,
            deviceID: "user-device"
        )
        let customCategory = try repository.createCategory(
            title: "My movement",
            includesInForecast: true
        )
        try repository.updateTask(
            taskID: definition.id,
            title: "Morning run",
            parentID: nil,
            categoryID: customCategory.id,
            colorHex: "00A870",
            iconName: "sunrise.fill",
            notes: "Keep this",
            estimatedSeconds: nil,
            dueAt: nil
        )
        try repository.archiveTask(taskID: definition.id)

        let replay = try coordinator.apply(roles: [role])

        #expect(replay == .noChanges)
        let fresh = ModelContext(context.container)
        let task = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[definition.id]
        )
        let assignment = try #require(
            try fresh.fetch(FetchDescriptor<TaskCategoryAssignment>())
                .logicalWinnersByTaskID()[definition.id]
        )
        #expect(task.title == "Morning run")
        #expect(task.notes == "Keep this")
        #expect(task.iconName == "sunrise.fill")
        #expect(task.colorHex == "00A870")
        #expect(task.isArchivedForLifecycle)
        #expect(assignment.categoryID == customCategory.id)
    }

    @Test
    func tombstonesAndStagedAssignmentsBlockOrdinaryBackgroundCreation()
        throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        let running = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let walking = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.walking)
        )
        _ = try coordinator.apply(roles: [.workout(.running)])

        let mutationContext = ModelContext(context.container)
        let categories = try mutationContext.fetch(
            FetchDescriptor<TaskCategory>()
        )
        let exerciseID = running.categoryID
        let exercise = try #require(
            categories.latestByID()[exerciseID]
        )
        exercise.deletedAt = Date()
        exercise.updatedAt = exercise.deletedAt!
        exercise.clientMutationID = UUID()
        try mutationContext.save()

        let blockedByCategory = try coordinator.apply(
            roles: [.workout(.walking)]
        )
        #expect(blockedByCategory == .noChanges)

        let stagedContext = ModelContext(context.container)
        let orphan = TaskCategoryAssignment(
            taskID: walking.id,
            categoryID: exerciseID,
            deviceID: "staged-import"
        )
        orphan.id = walking.categoryAssignmentID
        stagedContext.insert(orphan)
        try stagedContext.save()

        let blockedByAssignment = try coordinator.apply(
            roles: [.workout(.walking)]
        )
        #expect(blockedByAssignment == .noChanges)
        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .filter { $0.id == walking.id }
                .isEmpty
        )
    }

    @Test
    func explicitPostClearRecoveryRebuildsOnlyPreviouslyVisibleTemplates()
        throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        let role = AppleHealthTaskRole.sleep
        let definition = AppleHealthTaskCatalog.taskDefinition(for: role)
        let previousWorkout = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let excludedTombstone = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.cycling)
        )
        _ = try coordinator.apply(
            roles: [role, .workout(.running), .workout(.cycling)]
        )

        let clearContext = ModelContext(context.container)
        let task = try #require(
            try clearContext.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[definition.id]
        )
        task.archivedAt = Date(timeIntervalSince1970: 100)
        task.statusRaw = LegacyTaskStatusRaw.archived
        let clearedAt = Date(timeIntervalSince1970: 500)
        for model in try clearContext.fetch(FetchDescriptor<TaskNode>()) {
            tombstone(model, at: clearedAt)
        }
        for model in try clearContext.fetch(FetchDescriptor<TaskCategory>()) {
            tombstone(model, at: clearedAt)
        }
        for model in try clearContext.fetch(
            FetchDescriptor<TaskCategoryAssignment>()
        ) {
            tombstone(model, at: clearedAt)
        }
        try clearContext.save()

        let ordinary = try coordinator.apply(roles: [role])
        #expect(ordinary == .noChanges)

        let restored = try coordinator.apply(
            roles: [role],
            clearRecoveryTaskIDs: [
                definition.id,
                previousWorkout.id,
            ],
            now: Date(timeIntervalSince1970: 600)
        )

        #expect(
            Set(restored.restoredCategoryIDs) ==
                [definition.categoryID, previousWorkout.categoryID]
        )
        #expect(
            Set(restored.restoredTaskIDs) ==
                [definition.id, previousWorkout.id]
        )
        #expect(
            Set(restored.restoredAssignmentIDs) ==
                [
                    definition.categoryAssignmentID,
                    previousWorkout.categoryAssignmentID,
                ]
        )
        let fresh = ModelContext(context.container)
        let restoredTask = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[definition.id]
        )
        let excludedTask = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[excludedTombstone.id]
        )
        #expect(restoredTask.deletedAt == nil)
        #expect(restoredTask.isArchivedForLifecycle == false)
        #expect(
            restored.consumedClearRecoveryTaskIDs ==
                [definition.id, previousWorkout.id]
        )
        #expect(excludedTask.deletedAt != nil)
    }

    @Test
    func clearRecoveryRebuildsOneDefaultGraphAcrossDuplicatesAndRelationships()
        throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        let role = AppleHealthTaskRole.workout(.running)
        let definition = AppleHealthTaskCatalog.taskDefinition(for: role)
        _ = try coordinator.apply(roles: [role])

        let mutationContext = ModelContext(context.container)
        let repository = SwiftDataTaskRepository(
            context: mutationContext,
            deviceID: "user-device"
        )
        let customParent = try repository.createTask(
            title: "Custom parent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let customCategory = try repository.createCategory(
            title: "Custom category"
        )
        let duplicate = TaskNode(
            title: "Custom duplicate winner",
            parentID: customParent.id,
            deviceID: "user-device",
            colorHex: "00AA77",
            iconName: "sunrise.fill"
        )
        duplicate.id = definition.id
        duplicate.notes = "Discarded by Clear All"
        duplicate.archivedAt = Date()
        duplicate.statusRaw = LegacyTaskStatusRaw.archived
        duplicate.updatedAt = Date().addingTimeInterval(10)
        mutationContext.insert(duplicate)
        let fixedAssignment = try #require(
            try mutationContext.fetch(
                FetchDescriptor<TaskCategoryAssignment>()
            ).latestByID()[definition.categoryAssignmentID]
        )
        let customAssignment = TaskCategoryAssignment(
            taskID: definition.id,
            categoryID: customCategory.id,
            deviceID: "user-device"
        )
        mutationContext.insert(customAssignment)
        try mutationContext.save()
        #expect(
            try mutationContext.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[definition.id]?.title ==
                "Custom duplicate winner"
        )

        try mutationContext.performAtomicMutation {
            try SeedData.clearAllChanges(
                context: mutationContext,
                includesPreferences: true
            )
        }
        let lateImportDate = Date().addingTimeInterval(3_600)
        fixedAssignment.deletedAt = nil
        fixedAssignment.taskID = UUID()
        fixedAssignment.categoryID = customCategory.id
        fixedAssignment.updatedAt = lateImportDate
        fixedAssignment.clientMutationID = UUID()
        customAssignment.deletedAt = nil
        customAssignment.updatedAt = lateImportDate.addingTimeInterval(10)
        customAssignment.clientMutationID = UUID()
        try mutationContext.save()

        let recovery = try coordinator.apply(
            roles: [role],
            clearRecoveryTaskIDs: [definition.id],
            now: Date()
        )

        #expect(
            recovery.consumedClearRecoveryTaskIDs == [definition.id]
        )
        let fresh = ModelContext(context.container)
        let task = try #require(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[definition.id]
        )
        let category = try #require(
            try fresh.fetch(FetchDescriptor<TaskCategory>())
                .latestByID()[definition.categoryID]
        )
        let assignments = try fresh.fetch(
            FetchDescriptor<TaskCategoryAssignment>()
        )
        let logicalAssignment = try #require(
            assignments.logicalWinnersByTaskID()[definition.id]
        )
        #expect(task.deletedAt == nil)
        #expect(
            task.title ==
                AppStrings.localized(definition.titleLocalizationKey)
        )
        #expect(task.parentID == nil)
        #expect(task.path == TaskHierarchyMetadata.canonicalPath(for: task.id))
        #expect(task.depth == 0)
        #expect(task.notes == nil)
        #expect(task.isArchivedForLifecycle == false)
        #expect(category.deletedAt == nil)
        #expect(
            category.title == AppStrings.localized(
                AppleHealthTaskCatalog.categoryDefinition(
                    for: role.categoryRole
                ).titleLocalizationKey
            )
        )
        #expect(logicalAssignment.id == definition.categoryAssignmentID)
        #expect(logicalAssignment.categoryID == definition.categoryID)
        #expect(
            assignments.visibleDeduplicatedByID().filter {
                $0.taskID == definition.id
            }.map(\.id) == [definition.categoryAssignmentID]
        )
        #expect(
            try fresh.fetch(FetchDescriptor<TaskNode>())
                .latestByID()[customParent.id]?.deletedAt != nil
        )
    }

    @Test
    func staleActiveReceiptIsConsumedWithoutRevivingItsDeletedCategory()
        throws {
        let context = try makeTestContext()
        let coordinator = makeCoordinator(container: context.container)
        let role = AppleHealthTaskRole.workout(.running)
        let definition = AppleHealthTaskCatalog.taskDefinition(for: role)
        _ = try coordinator.apply(roles: [role])

        let mutationContext = ModelContext(context.container)
        let category = try #require(
            try mutationContext.fetch(FetchDescriptor<TaskCategory>())
                .latestByID()[definition.categoryID]
        )
        tombstone(category, at: Date())
        try mutationContext.save()

        let outcome = try coordinator.apply(
            roles: [role],
            clearRecoveryTaskIDs: [definition.id]
        )

        #expect(outcome.didMutate == false)
        #expect(
            outcome.consumedClearRecoveryTaskIDs == [definition.id]
        )
        let fresh = ModelContext(context.container)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskCategory>())
                .latestByID()[definition.categoryID]?.deletedAt != nil
        )
    }

    @Test
    func missingReceiptTaskWithStagedAssignmentRemainsPending()
        throws {
        let context = try makeTestContext()
        let definition = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.walking)
        )
        let categoryDefinition =
            AppleHealthTaskCatalog.categoryDefinition(for: .exercise)
        let category = TaskCategory(
            title: "Exercise",
            deviceID: "staged-import"
        )
        category.id = categoryDefinition.id
        let stagedAssignment = TaskCategoryAssignment(
            taskID: definition.id,
            categoryID: definition.categoryID,
            deviceID: "staged-import"
        )
        stagedAssignment.id = definition.categoryAssignmentID
        context.insert(category)
        context.insert(stagedAssignment)
        try context.save()

        let outcome = try makeCoordinator(
            container: context.container
        ).apply(
            roles: [.workout(.walking)],
            clearRecoveryTaskIDs: [definition.id]
        )

        #expect(outcome == .noChanges)
        #expect(outcome.consumedClearRecoveryTaskIDs.isEmpty)
        #expect(
            try context.fetch(FetchDescriptor<TaskNode>())
                .contains { $0.id == definition.id } == false
        )
    }

    @Test
    func injectedFailureRollsBackTheWholeCatalog() throws {
        enum InjectedFailure: Error {
            case stop
        }
        let context = try makeTestContext()
        let coordinator =
            StoreScopedAppleHealthTaskCatalogCommandCoordinator(
                container: context.container,
                writeAuthorization: .isolatedTestHarness,
                deviceID: "health-test",
                didReachCheckpoint: { checkpoint in
                    guard case .taskCreated = checkpoint else { return }
                    throw InjectedFailure.stop
                }
            )

        #expect(throws: InjectedFailure.self) {
            try coordinator.apply(roles: [.workout(.running)])
        }

        let fresh = ModelContext(context.container)
        #expect(try fresh.fetch(FetchDescriptor<TaskCategory>()).isEmpty)
        #expect(try fresh.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(
            try fresh.fetch(FetchDescriptor<TaskCategoryAssignment>())
                .isEmpty
        )
    }

    @Test
    func facadeAndCoordinatorCannotPersistHealthSamplesOrConstructModels()
        throws {
        let facade = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+AppleHealthTaskCatalog.swift"
        )
        let coordinator = try sourceText(
            "timetracker/Services/Tasks/StoreScopedAppleHealthTaskCatalogCommandCoordinator.swift"
        )
        let timelineFacade = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+AppleHealthTimeline.swift"
        )

        for source in [facade, coordinator] {
            #expect(source.contains("sourceBundleIdentifier") == false)
            #expect(source.contains("AppleHealthWorkoutSample") == false)
            #expect(source.contains("AppleHealthSleepSample") == false)
            #expect(source.contains("TimeSegment(") == false)
        }
        #expect(facade.contains("TaskNode(") == false)
        #expect(facade.contains("TaskCategory(") == false)
        #expect(facade.contains("context.insert") == false)
        #expect(
            facade.contains(
                "roles: AppleHealthTaskCatalog.allRoles"
            )
        )
        #expect(timelineFacade.contains("items.compactMap") == false)
        let templateCreation = try #require(
            timelineFacade.range(
                of: "materializeAppleHealthTaskCatalog("
            )
        )
        let authorizationRequest = try #require(
            timelineFacade.range(
                of: "try await appleHealthDataReader.requestReadAuthorization()"
            )
        )
        #expect(
            templateCreation.lowerBound < authorizationRequest.lowerBound
        )
    }

    private func makeCoordinator(
        container: ModelContainer
    ) -> StoreScopedAppleHealthTaskCatalogCommandCoordinator {
        StoreScopedAppleHealthTaskCatalogCommandCoordinator(
            container: container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "health-test"
        )
    }

    private func tombstone<Model>(
        _ model: Model,
        at date: Date
    ) where Model: SoftDeletablePersistentUUIDModel &
        ClientMutationTrackedModel {
        model.deletedAt = date
        model.updatedAt = date
        model.deviceID = "clear-test"
        model.clientMutationID = UUID()
    }
}
