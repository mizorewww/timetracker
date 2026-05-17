import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct DemoDataLifecycleTests {
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
    func stressDataProfileBuildsNestedMutableTaskGraph() throws {
        prepareAutomaticDemoSeeding(demoMode: .off)
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()
        let profile = StressDataProfile(
            name: "unit",
            rootCount: 2,
            maxDepth: 3,
            childrenPerNode: 2,
            checklistItemsPerTask: 2,
            segmentsPerTask: 1,
            categoryCount: 2,
            inboxItemCount: 5,
            countdownEventCount: 3
        )

        try SeedData.replaceWithStressData(context: context, profile: profile)

        let tasks = try context.fetch(FetchDescriptor<TaskNode>())
        let taskIDs = Set(tasks.map(\.id))
        let checklistItems = try context.fetch(FetchDescriptor<ChecklistItem>())
        let checklistVisuals = try context.fetch(FetchDescriptor<ChecklistItemVisual>())
        let sessions = try context.fetch(FetchDescriptor<TimeSession>())
        let segments = try context.fetch(FetchDescriptor<TimeSegment>())
        let inboxItems = try context.fetch(FetchDescriptor<InboxItem>())
        let inboxSuggestions = try context.fetch(FetchDescriptor<InboxSuggestion>())

        #expect(tasks.count == profile.estimatedTaskCount)
        #expect(tasks.contains { $0.depth == 2 && $0.parentID != nil })
        #expect(tasks.allSatisfy { $0.path.contains($0.id.uuidString) })
        #expect(tasks.allSatisfy { $0.estimatedSeconds != nil && $0.dueAt != nil && $0.notes?.isEmpty == false })
        #expect(checklistItems.count == tasks.count * profile.checklistItemsPerTask)
        #expect(checklistVisuals.count == checklistItems.count)
        #expect(sessions.count == tasks.count * profile.segmentsPerTask + min(3, tasks.count))
        #expect(segments.count == sessions.count)
        #expect(try context.fetch(FetchDescriptor<PomodoroRun>()).isEmpty == false)
        #expect(inboxItems.count == profile.inboxItemCount)
        #expect(inboxSuggestions.count == profile.inboxItemCount)
        #expect(try context.fetch(FetchDescriptor<CountdownEvent>()).count == profile.countdownEventCount)
        #expect(inboxItems.compactMap(\.suggestedTaskID).allSatisfy { taskIDs.contains($0) })
        let inboxTitleByID = Dictionary(uniqueKeysWithValues: inboxItems.map { ($0.id, $0.title) })
        #expect(inboxSuggestions.allSatisfy { $0.titleSnapshot == inboxTitleByID[$0.inboxItemID] })
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
    func automaticDemoDataCanBeDisabledByBuildConfiguration() throws {
        prepareAutomaticDemoSeeding(demoMode: .off)
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()

        try SeedData.ensureSeeded(context: context)

        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
    }

    @Test @MainActor
    func automaticDemoDataDoesNotSeedIntoPartiallyInitializedUserContentStore() throws {
        prepareAutomaticDemoSeeding()
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(context: context, deviceID: "test")
        _ = try repository.createCategory(
            title: "Learning",
            colorHex: "5856D6",
            iconName: "book",
            includesInForecast: true
        )

        try SeedData.ensureSeeded(context: context)

        #expect(try context.fetch(FetchDescriptor<TaskNode>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TaskCategory>()).map(\.title) == ["Learning"])
    }

    @Test
    func nonDebugBuildsCannotEnableOrCreateDemoData() throws {
        let configurationSource = try sourceText("timetracker/App/AppDemoDataConfiguration.swift")
        let seedSource = try sourceText("timetracker/App/SeedData.swift")
        let demoBuildSource = try sourceText("timetracker/App/SeedData+DemoBuild.swift")
        let stressBuildSource = try sourceText("timetracker/App/SeedData+StressBuild.swift")
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsDataSectionsViews.swift")

        #expect(configurationSource.contains("guard allowsDemoDataCreation else { return .off }"))
        #expect(seedSource.contains("guard AppDemoDataConfiguration.allowsDemoDataCreation else { return }"))
        #expect(seedSource.contains("throw SeedDataError.demoDataCreationUnavailable"))
        #expect(demoBuildSource.contains("#if DEBUG"))
        #expect(demoBuildSource.contains("#else\nextension SeedData"))
        #expect(stressBuildSource.contains("#if DEBUG"))
        #expect(stressBuildSource.contains("throw SeedDataError.demoDataCreationUnavailable"))
        #expect(settingsSource.contains("if allowsDemoDataCreation {"))
    }

    @Test @MainActor
    func screenshotDemoModeRebuildsDataOnLaunch() throws {
        prepareAutomaticDemoSeeding(demoMode: .replaceOnLaunch, disabled: true)
        defer { resetDemoSeedingDefaults() }
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        _ = try taskRepository.createTask(title: "Should Be Replaced", parentID: nil, colorHex: nil, iconName: nil)

        try SeedData.ensureSeeded(context: context)

        let titles = try context.fetch(FetchDescriptor<TaskNode>()).map(\.title)
        #expect(titles.contains("Should Be Replaced") == false)
        #expect(titles.contains("Time Tracker App"))
        #expect(SeedData.isAutomaticDemoSeedingDisabled == false)
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

    @MainActor
    private func prepareAutomaticDemoSeeding(
        mode: String = "Local",
        demoMode: AutomaticDemoDataMode = .seedIfEmpty,
        disabled: Bool = false,
        lastError: String? = nil
    ) {
        UserDefaults.standard.set(demoMode.rawValue, forKey: AppDemoDataConfiguration.overrideKey)
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
        UserDefaults.standard.removeObject(forKey: AppDemoDataConfiguration.overrideKey)
        UserDefaults.standard.removeObject(forKey: SeedData.automaticDemoSeedingDisabledKey)
        UserDefaults.standard.removeObject(forKey: AppCloudSync.modeKey)
        UserDefaults.standard.removeObject(forKey: AppCloudSync.errorKey)
        UserDefaults.standard.removeObject(forKey: AppCloudSync.accountStatusKey)
        UserDefaults.standard.removeObject(forKey: AppStressDataConfiguration.profileKey)
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressRootCount")
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressMaxDepth")
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressChildrenPerNode")
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressChecklistItemsPerTask")
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressSegmentsPerTask")
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressCategoryCount")
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressInboxItemCount")
        UserDefaults.standard.removeObject(forKey: "TimeTrackerStressCountdownEventCount")
    }
}
