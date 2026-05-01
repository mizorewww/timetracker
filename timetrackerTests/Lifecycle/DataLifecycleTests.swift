import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct DataLifecycleTests {
    @Test @MainActor
    func optimizeDatabaseRemovesLedgerRowsForSoftDeletedTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Temporary Client", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date().addingTimeInterval(-1_800)
        let session = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: nil
        )
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        run.sessionID = session.id
        run.state = .completed
        context.insert(run)
        try context.save()
        try taskRepository.softDeleteTask(taskID: task.id)

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        #expect(store.allSegments.count == 1)

        let removedCount = store.optimizeDatabase()

        #expect(removedCount == 3)
        #expect(try timeRepository.allSegments().isEmpty)
        #expect(try timeRepository.sessions().isEmpty)
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).contains { $0.id == task.id && $0.deletedAt != nil })
    }

    @Test @MainActor
    func optimizeDatabaseRemovesOnlyTrulyOrphanedLedgerRows() throws {
        let context = try makeTestContext()
        let missingTaskID = UUID()
        let session = TimeSession(taskID: missingTaskID, source: .manual, deviceID: "test")
        session.endedAt = Date()
        let segment = TimeSegment(
            sessionID: session.id,
            taskID: missingTaskID,
            source: .manual,
            deviceID: "test",
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date()
        )
        context.insert(session)
        context.insert(segment)
        try context.save()

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        let removedCount = store.optimizeDatabase()

        #expect(removedCount == 2)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).contains { $0.id == segment.id } == false)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).contains { $0.id == session.id } == false)
    }


    @Test @MainActor
    func demoDataContainsMultiDayAnalyticsAndActiveTimers() throws {
        prepareAutomaticDemoSeeding()
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()
        try SeedData.replaceWithDemoData(context: context)

        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(context: context, timeRepository: timeRepository, deviceID: "test")

        #expect(try taskRepository.allNodes().count >= 10)
        #expect(try timeRepository.allSegments().count >= 40)
        #expect(try timeRepository.activeSegments().count == 2)
        #expect(try pomodoroRepository.runs().contains { $0.state == .completed })

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let overview = store.analyticsOverview(for: .week)
        #expect(overview.grossSeconds > overview.wallSeconds)
        #expect(store.taskBreakdown(range: .week).isEmpty == false)
    }

    @Test @MainActor
    func replacingDemoDataClearsExistingLedgerBeforeSeeding() throws {
        prepareAutomaticDemoSeeding()
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let oldTask = try taskRepository.createTask(title: "Temporary Task", parentID: nil, colorHex: nil, iconName: nil)
        _ = try timeRepository.addManualSegment(
            taskID: oldTask.id,
            startedAt: Date().addingTimeInterval(-600),
            endedAt: Date(),
            note: nil
        )

        try SeedData.replaceWithDemoData(context: context)

        #expect(try taskRepository.allNodes().contains { $0.title == "Temporary Task" } == false)
        #expect(try timeRepository.allSegments().contains { $0.taskID == oldTask.id } == false)
        #expect(try timeRepository.activeSegments().count == 2)
        #expect(SeedData.isAutomaticDemoSeedingDisabled == false)
    }

    @Test @MainActor
    func clearingDemoDataKeepsUserCreatedRecords() throws {
        prepareAutomaticDemoSeeding()
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()
        try SeedData.replaceWithDemoData(context: context)

        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let userTask = try taskRepository.createTask(title: "Real Work", parentID: nil, colorHex: nil, iconName: nil)
        _ = try timeRepository.addManualSegment(
            taskID: userTask.id,
            startedAt: Date().addingTimeInterval(-900),
            endedAt: Date(),
            note: nil
        )

        try SeedData.clearDemoData(context: context)

        #expect(try taskRepository.allNodes().map(\.title) == ["Real Work"])
        #expect(try timeRepository.allSegments().count == 1)
        #expect(try timeRepository.activeSegments().isEmpty)
        #expect(SeedData.isAutomaticDemoSeedingDisabled)
    }

    @Test @MainActor
    func clearingDemoDataPreventsAutomaticReseedingOnNextLaunch() throws {
        prepareAutomaticDemoSeeding()
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()

        try SeedData.ensureSeeded(context: context)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty == false)

        try SeedData.clearDemoData(context: context)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(SeedData.isAutomaticDemoSeedingDisabled)

        try SeedData.ensureSeeded(context: context)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test @MainActor
    func rebuildingDemoDataReenablesAutomaticDemoSeeding() throws {
        prepareAutomaticDemoSeeding(disabled: true)
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()

        try SeedData.replaceWithDemoData(context: context)

        #expect(SeedData.isAutomaticDemoSeedingDisabled == false)
        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty == false)
    }

    @Test @MainActor
    func automaticDemoDataDoesNotSeedIntoCloudBackedStorage() throws {
        prepareAutomaticDemoSeeding(mode: AppCloudSync.modeICloud)
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()

        try SeedData.ensureSeeded(context: context)

        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test @MainActor
    func automaticDemoDataDoesNotSeedIntoFallbackStorage() throws {
        defer { resetDemoSeedingDefaults() }
        for mode in [AppCloudSync.modeLocalFallback, AppCloudSync.modeInMemoryFallback] {
            prepareAutomaticDemoSeeding(mode: mode, lastError: "Persistent store unavailable")
            let context = try makeTestContext()

            try SeedData.ensureSeeded(context: context)

            #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        }
    }

    @Test @MainActor
    func modelDefaultsSupportCloudKitCompatibleConstruction() throws {
        let context = try makeTestContext()
        let task = TaskNode(title: "Defaults", parentID: nil, deviceID: "test")
        let session = TimeSession(taskID: task.id, source: .timer, deviceID: "test")
        let segment = TimeSegment(sessionID: session.id, taskID: task.id, source: .timer, deviceID: "test")
        let run = PomodoroRun(taskID: task.id, deviceID: "test")
        let summary = DailySummary(date: Date(), taskID: task.id, grossSeconds: 0, wallClockSeconds: 0, pomodoroCount: 0, interruptionCount: 0)
        let countdown = CountdownEvent(title: "Launch", date: Date(), deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.defaultFocusMinutes.rawValue, valueJSON: "25", deviceID: "test")
        let checklistItem = ChecklistItem(taskID: task.id, title: "Checklist", deviceID: "test")
        let category = TaskCategory(title: "Work", deviceID: "test")
        let categoryAssignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")

        context.insert(task)
        context.insert(category)
        context.insert(categoryAssignment)
        context.insert(session)
        context.insert(segment)
        context.insert(run)
        context.insert(summary)
        context.insert(countdown)
        context.insert(preference)
        context.insert(checklistItem)
        try context.save()

        #expect(task.id.uuidString.isEmpty == false)
        #expect(task.status == .active)
        #expect(segment.source == .timer)
        #expect(run.state == .planned)
        #expect(summary.version == 1)
        #expect(countdown.deletedAt == nil)
        #expect(preference.deletedAt == nil)
        #expect(checklistItem.deletedAt == nil)
        #expect(category.includesInForecast)
        #expect(categoryAssignment.deletedAt == nil)
    }

    @Test @MainActor
    func cloudSyncedSchemaIncludesChecklistAndAllUserDataModels() throws {
        let requiredModelNames: Set<String> = [
            "TaskNode",
            "TaskCategory",
            "TaskCategoryAssignment",
            "TimeSession",
            "TimeSegment",
            "PomodoroRun",
            "CountdownEvent",
            "SyncedPreference",
            "ChecklistItem",
            "InboxItem"
        ]

        #expect(requiredModelNames.isSubset(of: TimeTrackerModelRegistry.cloudSyncedUserModelNames))

        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "TimeTrackerCloudSyncContract",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
        let context = ModelContext(container)
        let task = TaskNode(title: "Cloud task", parentID: nil, deviceID: "test")
        let category = TaskCategory(title: "Cloud category", deviceID: "test")
        let assignment = TaskCategoryAssignment(taskID: task.id, categoryID: category.id, deviceID: "test")
        let checklist = ChecklistItem(taskID: task.id, title: "Cloud checklist", deviceID: "test")
        let inboxItem = InboxItem(title: "Cloud inbox", deviceID: "test")
        let preference = SyncedPreference(key: AppPreferenceKey.showGrossAndWallTogether.rawValue, valueJSON: "true", deviceID: "test")

        context.insert(task)
        context.insert(category)
        context.insert(assignment)
        context.insert(checklist)
        context.insert(inboxItem)
        context.insert(preference)
        try context.save()

        #expect(try context.fetch(FetchDescriptor<ChecklistItem>()).map(\.title) == ["Cloud checklist"])
        #expect(try context.fetch(FetchDescriptor<InboxItem>()).map(\.title) == ["Cloud inbox"])
        #expect(try context.fetch(FetchDescriptor<TaskCategoryAssignment>()).map(\.categoryID) == [category.id])
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).map(\.key) == [AppPreferenceKey.showGrossAndWallTogether.rawValue])
    }

    @Test @MainActor
    func taskStatusCanBePlannedAndCompleted() throws {
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try repository.createTask(title: "Plan draft", parentID: nil, colorHex: nil, iconName: nil)

        try repository.setTaskStatus(taskID: task.id, status: .planned)
        #expect(try repository.task(id: task.id)?.status == .planned)

        try repository.setTaskStatus(taskID: task.id, status: .completed)
        #expect(try repository.task(id: task.id)?.status == .completed)
        #expect(TaskStatus.completed.displayName == AppStrings.localized("status.completed"))
    }

    @Test @MainActor
    func csvExportIncludesLedgerRows() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "CSV Task", parentID: nil, colorHex: nil, iconName: nil)
        let start = Date(timeIntervalSince1970: 2_000)
        _ = try timeRepository.addManualSegment(
            taskID: task.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(900),
            note: "Export note"
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        let csv = store.csvExport()

        #expect(csv.contains("Task,Path,Start,End,Duration Seconds,Source,Note"))
        #expect(csv.contains("CSV Task"))
        #expect(csv.contains("900"))
        #expect(csv.contains("Export note"))
    }

    @MainActor
    private func prepareAutomaticDemoSeeding(
        mode: String = "Local",
        disabled: Bool = false,
        lastError: String? = nil
    ) {
        UserDefaults.standard.set(disabled, forKey: SeedData.automaticDemoSeedingDisabledKey)
        UserDefaults.standard.set(mode, forKey: AppCloudSync.modeKey)
        if let lastError {
            UserDefaults.standard.set(lastError, forKey: AppCloudSync.errorKey)
        } else {
            UserDefaults.standard.removeObject(forKey: AppCloudSync.errorKey)
        }
    }

    @MainActor
    private func resetDemoSeedingDefaults() {
        UserDefaults.standard.removeObject(forKey: SeedData.automaticDemoSeedingDisabledKey)
        UserDefaults.standard.removeObject(forKey: AppCloudSync.modeKey)
        UserDefaults.standard.removeObject(forKey: AppCloudSync.errorKey)
        UserDefaults.standard.removeObject(forKey: AppCloudSync.accountStatusKey)
    }
}
