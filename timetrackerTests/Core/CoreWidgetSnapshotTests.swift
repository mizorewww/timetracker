import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreWidgetSnapshotTests {
    @Test
    func appGroupEntitlementStateIsExplicitAndConsistent() throws {
        let root = try projectRootURL()
        let appGroups = try readAppGroups(in: root.appending(path: "timetracker/timetracker.entitlements"))
        let widgetGroups = try readAppGroups(in: root.appending(path: "timetrackerWidgetExtension/timetrackerWidgetExtension.entitlements"))

        if appGroups.isEmpty || widgetGroups.isEmpty {
            let plan = try String(contentsOf: root.appending(path: "Docs/NextDevelopmentPlan.md"), encoding: .utf8)
            #expect(appGroups.isEmpty && widgetGroups.isEmpty)
            #expect(plan.contains("CLI currently cannot refresh the App Group provisioning profile"))
        } else {
            #expect(appGroups.contains(SharedWidgetSnapshotStore.suiteName))
            #expect(widgetGroups.contains(SharedWidgetSnapshotStore.suiteName))
            #expect(appGroups == widgetGroups)
        }
    }

    @Test @MainActor
    func widgetSnapshotCacheRoundTripsActiveTimerState() throws {
        let suiteName = "WidgetSnapshotTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let generatedAt = Date(timeIntervalSinceReferenceDate: 10_000)
        let taskID = UUID()
        let segmentID = UUID()
        let snapshot = WidgetSnapshot(
            generatedAt: generatedAt,
            todayGrossSeconds: 3_600,
            todayWallSeconds: 2_400,
            activeTimers: [
                WidgetTimerSnapshot(
                    id: segmentID,
                    taskID: taskID,
                    title: "Shortcut timer",
                    path: "Work / Planning",
                    startedAt: generatedAt.addingTimeInterval(-600),
                    colorHex: "#0A84FF",
                    iconName: "timer"
                )
            ],
            recentTasks: [
                WidgetRecentTaskSnapshot(
                    taskID: taskID,
                    title: "Write plan",
                    path: "Work",
                    colorHex: "#0A84FF",
                    iconName: "doc.text"
                )
            ]
        )
        let cache = SharedWidgetSnapshotStore(defaults: defaults)

        try cache.save(snapshot)

        #expect(cache.load() == snapshot)
    }

    @Test @MainActor
    func widgetSnapshotStoreDoesNotFallbackToStandardDefaultsWhenSharedContainerIsMissing() throws {
        let snapshot = WidgetSnapshot.empty
        let cache = SharedWidgetSnapshotStore(defaults: nil)

        #expect(cache.isAvailable == false)
        #expect(cache.load() == nil)
        #expect(throws: WidgetSnapshotStoreError.sharedContainerUnavailable) {
            try cache.save(snapshot)
        }
    }

    @Test @MainActor
    func widgetSnapshotUsesLedgerAndTaskReadModelsWithoutSwiftDataInWidget() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Widget task",
            parentID: nil,
            colorHex: "#34C759",
            iconName: "checkmark.circle"
        )
        let segment = try timeRepository.startTask(taskID: task.id, source: .timer)

        let snapshot = WidgetSnapshotCache.snapshot(
            activeSegments: [segment],
            taskByID: [task.id: task],
            taskParentPathByID: [task.id: "Work"],
            todayGrossSeconds: 120,
            todayWallSeconds: 120,
            generatedAt: segment.startedAt
        )

        #expect(snapshot.activeTimers.map(\.id) == [segment.id])
        #expect(snapshot.activeTimers.map(\.title) == ["Widget task"])
        #expect(snapshot.activeTimers.map(\.path) == ["Work"])
        #expect(snapshot.activeTimers.map(\.colorHex) == ["#34C759"])
        #expect(snapshot.activeTimers.map(\.iconName) == ["checkmark.circle"])
    }

    @Test @MainActor
    func widgetSnapshotIncludesRecentTaskQuickStartModels() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let first = try taskRepository.createTask(
            title: "First recent task",
            parentID: nil,
            colorHex: "#0A84FF",
            iconName: "bolt"
        )
        let second = try taskRepository.createTask(
            title: "Second recent task",
            parentID: nil,
            colorHex: "#BF5AF2",
            iconName: "book"
        )

        let snapshot = WidgetSnapshotCache.snapshot(
            activeSegments: [],
            taskByID: [first.id: first, second.id: second],
            taskParentPathByID: [
                first.id: "Work",
                second.id: "Study"
            ],
            recentTasks: [first, second],
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            generatedAt: Date(timeIntervalSinceReferenceDate: 20_000)
        )

        #expect(snapshot.recentTasks.map(\.taskID) == [first.id, second.id])
        #expect(snapshot.recentTasks.map(\.title) == ["First recent task", "Second recent task"])
        #expect(snapshot.recentTasks.map(\.path) == ["Work", "Study"])
        #expect(snapshot.recentTasks.map(\.iconName) == ["bolt", "book"])
        #expect(snapshot.recentTasks.map(\.colorHex) == ["#0A84FF", "#BF5AF2"])
    }
}

private func readAppGroups(in url: URL) throws -> Set<String> {
    let data = try Data(contentsOf: url)
    let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
    let dictionary = try #require(plist as? [String: Any])
    return Set(dictionary["com.apple.security.application-groups"] as? [String] ?? [])
}
