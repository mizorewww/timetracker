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
