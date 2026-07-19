import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskLedgerTests {
    @Test @MainActor
    func stoppingAfterAClockRollbackNeverCreatesNegativeLedgerTime() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Clock rollback",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        let futureStart = Date().addingTimeInterval(3_600)
        segment.startedAt = futureStart
        let session = try #require(try timeRepository.sessions().first)
        session.startedAt = futureStart
        try context.save()

        try timeRepository.stopSegment(segmentID: segment.id)

        let stoppedSegment = try #require(try timeRepository.allSegments().first)
        let stoppedSession = try #require(try timeRepository.sessions().first)
        #expect(stoppedSegment.endedAt == futureStart)
        #expect(stoppedSession.endedAt == futureStart)
    }

    @Test @MainActor
    func repositoryRejectsInvalidManualAndEditedTimeRanges() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test",
            nowProvider: { now }
        )
        let task = try taskRepository.createTask(
            title: "Validated range",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let start = now.addingTimeInterval(-120)

        #expect(throws: TimeTrackingRepositoryError.invalidTimeRange) {
            try timeRepository.addManualSegment(
                taskID: task.id,
                startedAt: start,
                endedAt: start,
                note: nil
            )
        }

        let segment = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: now.addingTimeInterval(-60),
            note: nil
        )
        #expect(throws: TimeTrackingRepositoryError.invalidTimeRange) {
            try timeRepository.updateSegment(
                segmentID: segment.id,
                taskID: task.id,
                startedAt: start,
                endedAt: start.addingTimeInterval(-1),
                note: nil
            )
        }
        #expect(try timeRepository.allSegments().first?.endedAt == now.addingTimeInterval(-60))
    }

    @Test @MainActor
    func repositoryRejectsFutureCompletedRecordsAndFutureActiveStarts() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test",
            nowProvider: { now }
        )
        let task = try taskRepository.createTask(
            title: "No future time",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        #expect(
            TimeTrackingRepositoryError.futureTime.errorDescription ==
                AppStrings.localized("segment.error.timeNotFuture")
        )

        #expect(throws: TimeTrackingRepositoryError.futureTime) {
            try timeRepository.addManualSegment(
                taskID: task.id,
                startedAt: now.addingTimeInterval(-60),
                endedAt: now.addingTimeInterval(1),
                note: nil
            )
        }

        let segment = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: now.addingTimeInterval(-120),
            endedAt: now.addingTimeInterval(-60),
            note: nil
        )
        #expect(throws: TimeTrackingRepositoryError.futureTime) {
            try timeRepository.updateSegment(
                segmentID: segment.id,
                taskID: task.id,
                startedAt: now.addingTimeInterval(1),
                endedAt: nil,
                note: nil
            )
        }
        #expect(throws: TimeTrackingRepositoryError.futureTime) {
            try timeRepository.updateSegment(
                segmentID: segment.id,
                taskID: task.id,
                startedAt: now.addingTimeInterval(-60),
                endedAt: now.addingTimeInterval(1),
                note: nil
            )
        }

        let stored = try #require(try timeRepository.allSegments().first)
        #expect(stored.startedAt == now.addingTimeInterval(-120))
        #expect(stored.endedAt == now.addingTimeInterval(-60))
    }

    @Test @MainActor
    func repositoryQueriesClipLegacyFutureRowsAtTheirReferenceDate() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 3_000_000)
        let task = TaskNode(title: "Clock skew", parentID: nil, deviceID: "test")
        let session = TimeSession(
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-600)
        )
        let spanning = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-600),
            endedAt: now.addingTimeInterval(600)
        )
        let futureOnly = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(60),
            endedAt: now.addingTimeInterval(600)
        )
        context.insert(task)
        context.insert(session)
        context.insert(spanning)
        context.insert(futureOnly)
        try context.save()

        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "test",
            nowProvider: { now }
        )
        let queried = try repository.segments(
            from: now.addingTimeInterval(-1_200),
            to: now.addingTimeInterval(1_200),
            now: now
        )

        #expect(queried.map(\.id) == [spanning.id])
        #expect(try repository.segments(from: now, to: now, now: now).isEmpty)
    }

    @Test @MainActor
    func todayMetricsClipCrossMidnightSegmentsToTheCalendarDay() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 14)))
        let task = TaskNode(title: "Night work", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .pomodoro, deviceID: "test", startedAt: dayStart.addingTimeInterval(-3_600))
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: dayStart.addingTimeInterval(-3_600),
            endedAt: dayStart.addingTimeInterval(3_600)
        )
        let store = makeTestStore()
        store.allSegments = [segment]
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        run.sessionID = session.id
        let now = dayStart.addingTimeInterval(2 * 3_600)

        #expect(store.todayGrossSeconds(now: now, calendar: calendar) == 3_600)
        #expect(store.todayWallSeconds(now: now, calendar: calendar) == 3_600)
        #expect(store.averageFocusSeconds(now: now, calendar: calendar) == 3_600)
        #expect(store.pomodoroElapsedFocusSeconds(for: run, now: now) == 2 * 3_600)
    }

    @Test @MainActor
    func pomodoroReadModelsUseIndexedLedgerHistoryWhenConfigured() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let dayStart = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14))
        )
        let context = try makeTestContext()
        let task = TaskNode(title: "Indexed focus", parentID: nil, deviceID: "test")
        let session = TimeSession(
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: dayStart.addingTimeInterval(-3_600)
        )
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: task.id,
            source: .pomodoro,
            deviceID: "test",
            startedAt: dayStart.addingTimeInterval(-3_600),
            endedAt: dayStart.addingTimeInterval(3_600)
        )
        context.insert(task)
        context.insert(session)
        context.insert(segment)
        try context.save()

        let store = makeTestStore()
        defer { store.pomodoroReconciliationTask?.cancel() }
        store.configureIfNeeded(context: context)
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        run.sessionID = session.id

        #expect(store.ledgerDomainStore.hasIndexedSegmentHistory)
        // Clear the published compatibility array to prove these reads are
        // served by the domain indexes after configuration.
        store.allSegments = []
        let now = dayStart.addingTimeInterval(2 * 3_600)

        #expect(store.averageFocusSeconds(now: now, calendar: calendar) == 3_600)
        #expect(store.pomodoroElapsedFocusSeconds(for: run, now: now) == 2 * 3_600)
    }

    @Test @MainActor
    func taskMovePreventsCyclesAndUpdatesHierarchy() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")

        let root = try repository.createTask(title: "Root", parentID: nil, colorHex: nil, iconName: nil)
        let child = try repository.createTask(title: "Child", parentID: root.id, colorHex: nil, iconName: nil)

        do {
            try repository.moveTask(taskID: root.id, newParentID: child.id, sortOrder: 10)
            Issue.record("Expected invalid move to throw")
        } catch TaskRepositoryError.invalidMove {
        } catch {
            Issue.record("Unexpected move error: \(error)")
        }
        #expect((try repository.task(id: root.id))?.parentID == nil)

        try repository.moveTask(taskID: child.id, newParentID: nil, sortOrder: 20)
        let movedTask = try repository.task(id: child.id)
        let moved = try #require(movedTask)
        #expect(moved.parentID == nil)
        #expect(moved.depth == 0)
    }

    @Test @MainActor
    func taskMutationsRecordTheCurrentDeviceAsTheLatestWriter() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let destination = try repository.createTask(
            title: "Destination",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let task = try repository.createTask(
            title: "Original",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )

        task.deviceID = "remote-device"
        try context.save()
        try repository.updateTask(
            taskID: task.id,
            title: "Updated",
            parentID: nil,
            categoryID: nil,
            colorHex: nil,
            iconName: nil,
            notes: nil,
            estimatedSeconds: nil,
            dueAt: nil
        )
        #expect(task.deviceID == "local-device")

        task.deviceID = "remote-device"
        try context.save()
        try repository.moveTask(taskID: task.id, newParentID: destination.id, sortOrder: 10)
        #expect(task.deviceID == "local-device")

        task.deviceID = "remote-device"
        try context.save()
        try repository.archiveTask(taskID: task.id)
        #expect(task.deviceID == "local-device")
    }

    @Test @MainActor
    func taskMoveKeepsPathsBoundedAndAvoidsUnchangedDescendantMutations() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let firstRoot = try repository.createTask(title: "First", parentID: nil, colorHex: nil, iconName: nil)
        let secondRoot = try repository.createTask(title: "Second", parentID: nil, colorHex: nil, iconName: nil)
        let child = try repository.createTask(title: "Child", parentID: firstRoot.id, colorHex: nil, iconName: nil)
        let grandchild = try repository.createTask(title: "Grandchild", parentID: child.id, colorHex: nil, iconName: nil)
        let previousGrandchildMutationID = grandchild.clientMutationID

        try repository.moveTask(taskID: child.id, newParentID: secondRoot.id, sortOrder: 10)

        let movedChild = try #require(try repository.task(id: child.id))
        let movedGrandchild = try #require(try repository.task(id: grandchild.id))
        #expect(movedChild.depth == 1)
        #expect(movedChild.path == "/" + child.id.uuidString)
        #expect(movedGrandchild.depth == 2)
        #expect(movedGrandchild.path == "/" + grandchild.id.uuidString)
        #expect(movedGrandchild.clientMutationID == previousGrandchildMutationID)
    }

    @Test @MainActor
    func taskHierarchyRejectsMissingParentsWithoutMutatingTheTask() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(title: "Root", parentID: nil, colorHex: nil, iconName: nil)
        let originalPath = task.path

        do {
            try repository.moveTask(taskID: task.id, newParentID: UUID(), sortOrder: 20)
            Issue.record("Expected a missing parent move to throw")
        } catch TaskRepositoryError.invalidMove {
        } catch {
            Issue.record("Unexpected move error: \(error)")
        }

        let unchanged = try #require(try repository.task(id: task.id))
        #expect(unchanged.parentID == nil)
        #expect(unchanged.depth == 0)
        #expect(unchanged.path == originalPath)
        #expect(!TaskTreeService().canMove(taskID: task.id, to: UUID(), tasks: [task]))

        do {
            _ = try repository.createTask(
                title: "Orphan",
                parentID: UUID(),
                colorHex: nil,
                iconName: nil
            )
            Issue.record("Expected creating an orphan task to throw")
        } catch TaskRepositoryError.invalidMove {
        } catch {
            Issue.record("Unexpected create error: \(error)")
        }
        let remainingCount = try repository.allNodes().count
        #expect(remainingCount == 1)
    }

    @Test @MainActor
    func taskTreeServiceFiltersInvalidParentsAndFlattensVisibleRows() throws {
        let parent = TaskNode(title: "Parent", parentID: nil, deviceID: "test")
        let child = TaskNode(title: "Child", parentID: parent.id, deviceID: "test")
        let grandchild = TaskNode(title: "Grandchild", parentID: child.id, deviceID: "test")
        let sibling = TaskNode(title: "Sibling", parentID: nil, deviceID: "test")
        let service = TaskTreeService()
        let indexes = service.indexes(tasks: [parent, child, grandchild, sibling])

        let validParents = service.validParentTasks(for: parent.id, tasks: [parent, child, grandchild, sibling])
        #expect(validParents.map(\.id) == [sibling.id])

        let rows = TaskTreeFlattener.visibleRows(
            rootTasks: indexes.childrenByParentID[nil] ?? [],
            children: { indexes.childrenByParentID[$0.id] ?? [] },
            expandedTaskIDs: [parent.id]
        )

        #expect(rows.map(\.taskID) == [parent.id, child.id, sibling.id])
        #expect(rows.map(\.depth) == [0, 1, 0])
        #expect(rows.first?.hasChildren == true)
        #expect(rows.first?.isExpanded == true)
    }

    @Test @MainActor
    func taskTreeCandidatesHonorTombstonesAndSiblingTiesAreDeterministic() throws {
        let source = TaskNode(title: "Source", parentID: nil, deviceID: "test")
        let olderParent = TaskNode(title: "Removed", parentID: nil, deviceID: "test")
        let newerTombstone = TaskNode(title: "Removed", parentID: nil, deviceID: "cloud")
        newerTombstone.id = olderParent.id
        olderParent.updatedAt = Date(timeIntervalSinceReferenceDate: 100)
        newerTombstone.updatedAt = Date(timeIntervalSinceReferenceDate: 200)
        newerTombstone.deletedAt = newerTombstone.updatedAt

        let laterID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let earlierID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let later = TaskNode(title: "Same", parentID: nil, deviceID: "test", sortOrder: 10)
        let earlier = TaskNode(title: "Same", parentID: nil, deviceID: "test", sortOrder: 10)
        let sharedCreationDate = Date(timeIntervalSinceReferenceDate: 300)
        later.id = laterID
        earlier.id = earlierID
        later.createdAt = sharedCreationDate
        earlier.createdAt = sharedCreationDate

        let service = TaskTreeService()
        let candidates = service.validParentTasks(
            for: source.id,
            tasks: [source, olderParent, newerTombstone, later, earlier]
        )
        #expect(candidates.map(\.id) == [laterID, earlierID])
        #expect(service.canMove(
            taskID: source.id,
            to: olderParent.id,
            tasks: [source, olderParent, newerTombstone]
        ) == false)

        let indexes = service.indexes(tasks: [later, earlier])
        #expect(indexes.childrenByParentID[nil]?.map(\.id) == [earlierID, laterID])
    }

    @Test @MainActor
    func cyclicRemoteHierarchyIsDeterministicallyDetachedAndEveryTaskRemainsVisible() throws {
        let firstID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let secondID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let first = TaskNode(title: "First", parentID: secondID, deviceID: "device-a")
        first.id = firstID
        let second = TaskNode(title: "Second", parentID: firstID, deviceID: "device-b")
        second.id = secondID

        let repairPlan = TaskHierarchyRepairPlan(tasks: [first, second])
        #expect(repairPlan.cycleBreakerTaskIDs == [firstID])
        #expect(repairPlan.taskIDsToDisplayAsRoots == [firstID])

        let indexes = TaskTreeService().indexes(tasks: [first, second])
        let rows = TaskTreeFlattener.visibleRows(
            rootTasks: indexes.childrenByParentID[nil] ?? [],
            children: { indexes.childrenByParentID[$0.id] ?? [] },
            expandedTaskIDs: [firstID, secondID]
        )
        #expect(rows.map(\.taskID) == [firstID, secondID])
        #expect(Set(rows.map(\.taskID)) == [firstID, secondID])

        let context = try makeTestContext()
        context.insert(first)
        context.insert(second)
        try context.save()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "repair-device")
        #expect(try repository.repairInvalidHierarchy() == [firstID, secondID])

        let repaired = try repository.allNodes().latestByID()
        #expect(repaired[firstID]?.parentID == nil)
        #expect(repaired[firstID]?.depth == 0)
        #expect(repaired[firstID]?.deviceID == "repair-device")
        #expect(repaired[secondID]?.parentID == firstID)
        #expect(repaired[secondID]?.depth == 1)
        #expect(repaired[secondID]?.deviceID == "repair-device")
    }

    @Test @MainActor
    func taskWithMissingRemoteParentIsRecoveredAsARoot() throws {
        let task = TaskNode(title: "Orphaned during staged import", parentID: UUID(), deviceID: "cloud")
        let plan = TaskHierarchyRepairPlan(tasks: [task])
        #expect(plan.cycleBreakerTaskIDs.isEmpty)
        #expect(plan.taskIDsToDisplayAsRoots == [task.id])
        let indexes = TaskTreeService().indexes(tasks: [task])
        #expect(indexes.childrenByParentID[nil]?.map(\.id) == [task.id])
    }

    @Test @MainActor
    func taskRefreshPreservesParentIdentityAcrossStagedCloudImport() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "local-device")
        let parentID = UUID()
        let child = TaskNode(
            title: "Child arrived first",
            parentID: parentID,
            deviceID: "cloud-device"
        )
        child.depth = 1
        child.path = TaskHierarchyMetadata.canonicalPath(for: child.id)
        let originalUpdatedAt = Date(timeIntervalSinceReferenceDate: 10_000)
        let originalMutationID = UUID()
        child.updatedAt = originalUpdatedAt
        child.clientMutationID = originalMutationID
        context.insert(child)
        try context.save()

        let appStore = makeTestStore()
        appStore.configureIfNeeded(context: context)
        var taskStore = TaskStore()
        try taskStore.refresh(repository: repository)
        try taskStore.refreshTaskScoped(taskIDs: [child.id], repository: repository)

        #expect(context.hasChanges == false)
        let stagedChild = try #require(try repository.task(id: child.id))
        #expect(stagedChild.parentID == parentID)
        #expect(stagedChild.updatedAt == originalUpdatedAt)
        #expect(stagedChild.clientMutationID == originalMutationID)
        #expect(stagedChild.deviceID == "cloud-device")
        let stagedIndexes = TaskTreeService().indexes(tasks: taskStore.tasks)
        #expect(stagedIndexes.childrenByParentID[nil]?.map(\.id) == [child.id])
        #expect(appStore.tasks.first?.parentID == parentID)

        let parent = TaskNode(title: "Parent arrived later", parentID: nil, deviceID: "cloud-device")
        parent.id = parentID
        context.insert(parent)
        try context.save()

        try taskStore.refreshTaskScoped(taskIDs: [parent.id, child.id], repository: repository)

        #expect(context.hasChanges == false)
        let completedIndexes = TaskTreeService().indexes(tasks: taskStore.tasks)
        #expect(completedIndexes.childrenByParentID[nil]?.map(\.id) == [parent.id])
        #expect(completedIndexes.childrenByParentID[parent.id]?.map(\.id) == [child.id])
        let completedChild = try #require(try repository.task(id: child.id))
        #expect(completedChild.parentID == parent.id)
        #expect(completedChild.updatedAt == originalUpdatedAt)
        #expect(completedChild.clientMutationID == originalMutationID)
    }

    @Test @MainActor
    func deeplyNestedTaskPathsAreIterativeAndDisplayBounded() throws {
        var tasks: [TaskNode] = []
        var parentID: UUID?
        for index in 0..<5_000 {
            let task = TaskNode(title: "Level \(index)", parentID: parentID, deviceID: "test")
            tasks.append(task)
            parentID = task.id
        }

        let service = TaskTreeService()
        let indexes = service.indexes(tasks: tasks)
        let deepest = try #require(tasks.last)
        let displayedPath = try #require(indexes.taskPathByID[deepest.id])

        #expect(displayedPath.hasPrefix("… / "))
        #expect(displayedPath.components(separatedBy: " / ").count == TaskTreeService.maximumDisplayedPathComponents + 1)
        #expect(service.descendantIDs(of: tasks[0].id, tasks: tasks).count == tasks.count - 1)
    }

    @Test @MainActor
    func timerStopUsesSegmentsAsLedger() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)

        let first = try timeRepository.startTask(taskID: task.id, source: .timer)
        #expect(try timeRepository.activeSegments().count == 1)

        try timeRepository.stopSession(sessionID: first.sessionID)
        #expect(try timeRepository.activeSegments().isEmpty)

        let sessions = try timeRepository.sessions()
        #expect(sessions.first?.endedAt != nil)
    }

    @Test @MainActor
    func segmentEditAndSoftDeleteKeepLedgerConsistent() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let firstTask = try taskRepository.createTask(title: "Design", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Writing", parentID: nil, colorHex: nil, iconName: nil)

        let start = Date(timeIntervalSince1970: 2_000)
        let segment = try timeRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_800),
            note: "Original"
        )

        try timeRepository.updateSegment(
            segmentID: segment.id,
            taskID: secondTask.id,
            startedAt: start.addingTimeInterval(300),
            endedAt: start.addingTimeInterval(2_100),
            note: "Corrected"
        )

        let editedSegments = try timeRepository.segments(from: start, to: start.addingTimeInterval(3_000))
        let updated = try #require(editedSegments.first { $0.id == segment.id })
        #expect(updated.taskID == secondTask.id)
        #expect(updated.startedAt == start.addingTimeInterval(300))
        #expect(updated.endedAt == start.addingTimeInterval(2_100))

        try timeRepository.softDeleteSegment(segmentID: segment.id)
        #expect(try timeRepository.segments(from: start, to: start.addingTimeInterval(3_000)).isEmpty)
    }

    @Test @MainActor
    func finishedSegmentCannotBeReopenedThroughRepositoryOrStore() throws {
        let context = try makeTestContext()
        let now = Date(timeIntervalSinceReferenceDate: 4_000_000)
        let task = try SwiftDataTaskRepository(context: context, deviceID: "task-device").createTask(
            title: "Historical record",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let repository = SwiftDataTimeTrackingRepository(
            context: context,
            deviceID: "ledger-device",
            nowProvider: { now }
        )
        let start = now.addingTimeInterval(-600)
        let end = now.addingTimeInterval(-300)
        let segment = try repository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: end,
            note: "Original note"
        )
        let session = try #require(try repository.sessions().first { $0.id == segment.sessionID })
        let originalSegmentUpdatedAt = segment.updatedAt
        let originalSessionUpdatedAt = session.updatedAt
        let originalMutationID = session.clientMutationID

        #expect(
            TimeTrackingRepositoryError.closedSegmentCannotReopen.errorDescription ==
                AppStrings.localized("segment.error.cannotReopen")
        )
        #expect(throws: TimeTrackingRepositoryError.closedSegmentCannotReopen) {
            try repository.updateSegment(
                segmentID: segment.id,
                taskID: task.id,
                startedAt: start,
                endedAt: nil,
                note: "Must not persist"
            )
        }
        #expect(segment.endedAt == end)
        #expect(segment.updatedAt == originalSegmentUpdatedAt)
        #expect(session.note == "Original note")
        #expect(session.updatedAt == originalSessionUpdatedAt)
        #expect(session.clientMutationID == originalMutationID)

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = try #require(store.segmentEditorDraft(for: segment))
        #expect(draft.wasActive == false)
        draft.isActive = true

        #expect(store.saveSegmentDraft(draft) == false)
        #expect(store.errorMessage == AppStrings.localized("segment.error.cannotReopen"))
        #expect(segment.endedAt == end)
        #expect(session.note == "Original note")
    }

    @Test @MainActor
    func deletingTheEarliestSegmentRebuildsTheRemainingSessionBounds() throws {
        let context = try makeTestContext()
        let taskID = UUID()
        let start = Date(timeIntervalSinceReferenceDate: 10_000)
        let session = TimeSession(
            taskID: taskID,
            source: .manual,
            deviceID: "creation-device",
            startedAt: start
        )
        session.endedAt = start.addingTimeInterval(300)
        let earliest = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .manual,
            deviceID: "creation-device",
            startedAt: start,
            endedAt: start.addingTimeInterval(100)
        )
        let remaining = TimeSegment(
            sessionID: session.id,
            taskID: taskID,
            source: .manual,
            deviceID: "creation-device",
            startedAt: start.addingTimeInterval(200),
            endedAt: start.addingTimeInterval(300)
        )
        context.insert(session)
        context.insert(earliest)
        context.insert(remaining)
        try context.save()

        try SwiftDataTimeTrackingRepository(context: context, deviceID: "delete-device")
            .softDeleteSegment(segmentID: earliest.id)

        #expect(session.deletedAt == nil)
        #expect(session.startedAt == remaining.startedAt)
        #expect(session.endedAt == remaining.endedAt)
        #expect(session.deviceID == "delete-device")
    }

    @Test @MainActor
    func ledgerMutationsRefreshSessionConflictMetadata() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "task-device")
        let firstTask = try taskRepository.createTask(title: "First", parentID: nil, colorHex: nil, iconName: nil)
        let secondTask = try taskRepository.createTask(title: "Second", parentID: nil, colorHex: nil, iconName: nil)
        let creationRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "creation-device")

        let activeSegment = try creationRepository.startTask(taskID: firstTask.id, source: .timer)
        let activeSession = try #require(
            try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == activeSegment.sessionID }
        )
        let creationMutationID = activeSession.clientMutationID
        try SwiftDataTimeTrackingRepository(context: context, deviceID: "segment-stop-device")
            .stopSegment(segmentID: activeSegment.id)
        #expect(activeSegment.deviceID == "segment-stop-device")
        #expect(activeSession.deviceID == "segment-stop-device")
        #expect(activeSession.clientMutationID != creationMutationID)

        let start = Date(timeIntervalSince1970: 20_000)
        let manualSegment = try creationRepository.addManualSegment(
            taskID: firstTask.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            note: "Original"
        )
        let manualSession = try #require(
            try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == manualSegment.sessionID }
        )
        let manualCreationMutationID = manualSession.clientMutationID
        let editRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "edit-device")
        try editRepository.updateSegment(
            segmentID: manualSegment.id,
            taskID: secondTask.id,
            startedAt: start.addingTimeInterval(60),
            endedAt: start.addingTimeInterval(900),
            note: "Edited"
        )
        #expect(manualSegment.deviceID == "edit-device")
        #expect(manualSession.deviceID == "edit-device")
        #expect(manualSession.clientMutationID != manualCreationMutationID)

        let editedMutationID = manualSession.clientMutationID
        try SwiftDataTimeTrackingRepository(context: context, deviceID: "delete-device")
            .softDeleteSegment(segmentID: manualSegment.id)
        #expect(manualSegment.deviceID == "delete-device")
        #expect(manualSession.deletedAt != nil)
        #expect(manualSession.deviceID == "delete-device")
        #expect(manualSession.clientMutationID != editedMutationID)

        let sessionStopSegment = try creationRepository.startTask(taskID: firstTask.id, source: .timer)
        let sessionToStop = try #require(
            try context.fetch(FetchDescriptor<TimeSession>()).first { $0.id == sessionStopSegment.sessionID }
        )
        let sessionStopCreationMutationID = sessionToStop.clientMutationID
        try SwiftDataTimeTrackingRepository(context: context, deviceID: "session-stop-device")
            .stopSession(sessionID: sessionToStop.id)
        #expect(sessionStopSegment.deviceID == "session-stop-device")
        #expect(sessionToStop.deviceID == "session-stop-device")
        #expect(sessionToStop.clientMutationID != sessionStopCreationMutationID)
    }

    @Test @MainActor
    func activeSegmentEditorRejectsFutureStartsWithoutMutatingLedger() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Active", parentID: nil, colorHex: nil, iconName: nil)
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        var draft = try #require(store.segmentEditorDraft(for: segment))
        draft.startedAt = Date().addingTimeInterval(3_600)
        draft.isActive = true

        #expect(store.saveSegmentDraft(draft) == false)
        #expect(store.errorMessage == AppStrings.localized("segment.error.startNotFuture"))
        let unchanged = try #require(try timeRepository.activeSegments().first { $0.id == segment.id })
        #expect(unchanged.startedAt == segment.startedAt)
    }

    @Test
    func invalidationRangeNormalizesReversedRemoteDates() {
        let later = Date(timeIntervalSinceReferenceDate: 2_000)
        let earlier = Date(timeIntervalSinceReferenceDate: 1_000)
        let range = StoreInvalidationRange(start: later, end: earlier)

        #expect(range.start == earlier)
        #expect(range.end == later)
        #expect(DateInterval(start: range.start, end: range.end).duration == 1_000)
    }

    @Test @MainActor
    func segmentRangeQueryUsesExplicitSnapshotDateForActiveSegments() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Active", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test", startedAt: start, titleSnapshot: task.title)
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test", startedAt: start, endedAt: nil)
        context.insert(session)
        context.insert(segment)
        try context.save()

        let beforeRange = try timeRepository.segments(
            from: start.addingTimeInterval(600),
            to: start.addingTimeInterval(1_200),
            now: start.addingTimeInterval(300)
        )
        let insideRange = try timeRepository.segments(
            from: start.addingTimeInterval(600),
            to: start.addingTimeInterval(1_200),
            now: start.addingTimeInterval(900)
        )

        #expect(beforeRange.isEmpty)
        #expect(insideRange.map(\.id) == [segment.id])
    }

    @Test @MainActor
    func manualSegmentStoresAndUpdatesSessionNote() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Writing", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 10_000)
        let segment = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(1_200),
            note: "Initial note"
        )

        var session = try #require(try timeRepository.sessions().first { $0.id == segment.sessionID })
        #expect(session.note == "Initial note")
        #expect(session.titleSnapshot == "Writing")

        try timeRepository.updateSegment(
            segmentID: segment.id,
            taskID: task.id,
            startedAt: start.addingTimeInterval(60),
            endedAt: start.addingTimeInterval(1_500),
            note: "Corrected note"
        )

        session = try #require(try timeRepository.sessions().first { $0.id == segment.sessionID })
        #expect(session.note == "Corrected note")
        #expect(session.startedAt == start.addingTimeInterval(60))
        #expect(session.endedAt == start.addingTimeInterval(1_500))
    }


    @Test @MainActor
    func taskListRollupDurationsIncludeHistoricalDescendantTaskTime() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let parent = try taskRepository.createTask(title: "Parent", parentID: nil, colorHex: nil, iconName: nil)
        let child = try taskRepository.createTask(title: "Child", parentID: parent.id, colorHex: nil, iconName: nil)
        let grandchild = try taskRepository.createTask(title: "Grandchild", parentID: child.id, colorHex: nil, iconName: nil)
        let calendar = Calendar.current
        let currentDayStart = calendar.startOfDay(for: Date())
        let testDayStart = try #require(calendar.date(byAdding: .day, value: -2, to: currentDayStart))
        let now = testDayStart.addingTimeInterval(12 * 3_600)
        let startOfDay = calendar.startOfDay(for: now)

        _ = try timeRepository.addManualSegment(
            taskID: parent.id,
            startedAt: startOfDay.addingTimeInterval(9 * 3_600),
            endedAt: startOfDay.addingTimeInterval(9 * 3_600 + 600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: child.id,
            startedAt: startOfDay.addingTimeInterval(10 * 3_600),
            endedAt: startOfDay.addingTimeInterval(10 * 3_600 + 900),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: grandchild.id,
            startedAt: startOfDay.addingTimeInterval(11 * 3_600),
            endedAt: startOfDay.addingTimeInterval(11 * 3_600 + 300),
            note: nil
        )
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfDay) ?? startOfDay.addingTimeInterval(-86_400)
        _ = try timeRepository.addManualSegment(
            taskID: child.id,
            startedAt: yesterday.addingTimeInterval(14 * 3_600),
            endedAt: yesterday.addingTimeInterval(14 * 3_600 + 2_400),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(store.secondsForTaskToday(parent, now: now) == 600)
        #expect(store.secondsForTaskTodayRollup(parent, now: now) == 1_800)
        #expect(store.secondsForTaskTodayRollup(child, now: now) == 1_200)
        #expect(store.secondsForTaskTotal(parent) == 600)
        #expect(store.secondsForTaskTotalRollup(parent, now: now) == 4_200)
        #expect(store.secondsForTaskTotalRollup(child, now: now) == 3_600)
        #expect(store.rollup(for: parent.id)?.workedSeconds == 4_200)
    }
}
