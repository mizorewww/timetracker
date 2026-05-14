import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreWatchCommandTests {
    @Test
    func watchConnectivityPayloadCodecRoundTripsTimerCommands() throws {
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: UUID(),
            segmentID: nil,
            issuedAt: Date(timeIntervalSinceReferenceDate: 1_234),
            deviceID: "watch-device"
        )

        let payload = WatchConnectivityPayloadCodec.encode(command: command)
        let decoded = try #require(WatchConnectivityPayloadCodec.decodeCommand(from: payload))

        #expect(decoded == command)
    }

    @Test
    func watchConnectivityPayloadCodecRoundTripsStateSnapshots() throws {
        let timerID = UUID()
        let taskID = UUID()
        let snapshot = WatchStateSnapshot(
            generatedAt: Date(timeIntervalSinceReferenceDate: 2_000),
            todayGrossSeconds: 3_600,
            todayWallSeconds: 2_400,
            activeTimers: [
                WatchActiveTimerSnapshot(
                    id: timerID,
                    taskID: taskID,
                    title: "Watch timer",
                    path: "Work",
                    startedAt: Date(timeIntervalSinceReferenceDate: 1_900),
                    colorHex: "#0A84FF",
                    iconName: "timer"
                )
            ],
            recentTasks: [
                WatchRecentTaskSnapshot(
                    taskID: taskID,
                    title: "Continue",
                    path: "Work",
                    colorHex: "#0A84FF",
                    iconName: "bolt"
                )
            ]
        )

        let payload = WatchConnectivityPayloadCodec.encode(state: snapshot)
        let decoded = try #require(WatchConnectivityPayloadCodec.decodeState(from: payload))

        #expect(decoded == snapshot)
    }

    @Test @MainActor
    func watchSnapshotRanksPinnedTasksBeforeRecentTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pinned = try taskRepository.createTask(title: "Pinned", parentID: nil, colorHex: "#0A84FF", iconName: "pin")
        let frequent = try taskRepository.createTask(title: "Frequent", parentID: nil, colorHex: "#30D158", iconName: "bolt")
        let occasional = try taskRepository.createTask(title: "Occasional", parentID: nil, colorHex: "#FF9F0A", iconName: "book")
        let start = Date(timeIntervalSinceReferenceDate: 5_000)

        _ = try timeRepository.addManualSegment(
            taskID: occasional.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequent.id,
            startedAt: start.addingTimeInterval(1_000),
            endedAt: start.addingTimeInterval(1_600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequent.id,
            startedAt: start.addingTimeInterval(2_000),
            endedAt: start.addingTimeInterval(2_600),
            note: nil
        )

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.setQuickStartTaskIDs([pinned.id])

        let snapshot = store.watchStateSnapshot(now: start.addingTimeInterval(3_000))

        #expect(Array(snapshot.recentTasks.map(\.taskID).prefix(3)) == [pinned.id, frequent.id, occasional.id])
        #expect(snapshot.recentTasks.first?.title == "Pinned")
        #expect(snapshot.recentTasks.first?.iconName == "pin")
    }

    @Test @MainActor
    func watchSnapshotIncludesEveryAvailableTaskAfterPinnedAndRecentTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        var createdTasks: [TaskNode] = []

        for index in 0..<12 {
            createdTasks.append(
                try taskRepository.createTask(
                    title: "Task \(index)",
                    parentID: nil,
                    colorHex: nil,
                    iconName: nil
                )
            )
        }

        let archivedTask = createdTasks[11]
        archivedTask.status = .archived
        let deletedTask = createdTasks[10]
        deletedTask.deletedAt = Date(timeIntervalSinceReferenceDate: 10)
        try context.save()

        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)
        store.setQuickStartTaskIDs([createdTasks[7].id, createdTasks[2].id])

        let snapshot = store.watchStateSnapshot(now: Date(timeIntervalSinceReferenceDate: 20))

        #expect(snapshot.recentTasks.count == 10)
        #expect(Array(snapshot.recentTasks.map(\.taskID).prefix(2)) == [createdTasks[7].id, createdTasks[2].id])
        #expect(!snapshot.recentTasks.map(\.taskID).contains(archivedTask.id))
        #expect(!snapshot.recentTasks.map(\.taskID).contains(deletedTask.id))
    }

    @Test
    func watchDashboardUsesTwoPageTaskAndRunningLayout() throws {
        let source = try sourceText("timetrackerWatchApp/WatchDashboardView.swift")

        #expect(source.contains("TabView"))
        #expect(source.contains(".tabViewStyle(.page"))
        #expect(source.contains("WatchTaskShortcutsPage"))
        #expect(source.contains("WatchRunningPage"))
        #expect(source.contains("toggleTask"))
        #expect(source.contains("snapshot.activeTimers.first(where: { $0.taskID == task.taskID })"))
        #expect(!source.contains("Text(activeTimer.startedAt"))
        #expect(!source.contains("Label(\"watch.stop\""))
        #expect(!source.contains("Button(role: .destructive"))
    }

    @Test
    func watchConnectivityBridgeDeclaresApplicationContextAndQueuedCommandHandling() throws {
        let source = try sourceText("timetracker/Services/SystemIntegration/WatchConnectivityBridge.swift")

        #expect(source.contains("updateApplicationContext"))
        #expect(source.contains("didReceiveUserInfo"))
        #expect(source.contains("didReceiveMessage"))
        #expect(source.contains("WatchConnectivityPayloadCodec.decodeCommand"))
    }

    @Test
    func storeRefreshPublishesWatchStateWhenLedgerOrTasksChange() throws {
        let source = try sourceText("timetracker/Stores/Refresh/StoreRefreshCoordinator.swift")
        let facade = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+WatchSnapshot.swift")

        #expect(source.contains("syncWatchSnapshotIfAvailable"))
        #expect(facade.contains("watchTaskShortcuts()"))
        #expect(facade.contains("preferences.quickStartTaskIDs"))
        #expect(facade.contains("WatchConnectivityBridge.shared.updateApplicationContext"))
    }

    @Test
    func contentViewActivatesWatchBridgeAndRoutesIncomingCommands() throws {
        let contentView = try sourceText("timetracker/App/ContentView.swift")
        let facade = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+WatchSnapshot.swift")

        #expect(contentView.contains("WatchConnectivityBridge.shared.commandHandler"))
        #expect(contentView.contains("WatchConnectivityBridge.shared.activateIfSupported"))
        #expect(facade.contains("handleWatchCommand"))
        #expect(facade.contains("WatchCommandProcessor().process"))
    }

    @Test @MainActor
    func watchStartCommandUsesWatchSourceAndIsDurablyDeduped() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Watch task", parentID: nil, colorHex: nil, iconName: nil)
        let receiptStore = InMemoryWatchCommandReceiptStore()
        let processor = WatchCommandProcessor(receiptStore: receiptStore)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: task.id,
            segmentID: nil,
            issuedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            deviceID: "watch-test"
        )

        let firstResult = try processor.process(command, allowParallelTimers: true, context: context)
        try SystemActionCommandHandler().stopTimer(taskID: task.id, context: context)
        let duplicateResult = try processor.process(command, allowParallelTimers: true, context: context)

        let segments = try context.fetch(FetchDescriptor<TimeSegment>())
        #expect(firstResult.isProcessed)
        #expect(duplicateResult == .duplicate(command.id))
        #expect(segments.count == 1)
        #expect(segments.first?.source == .watch)
    }

    @Test @MainActor
    func missingWatchStartCommandCanBeRetriedAfterTaskArrives() throws {
        let context = try makeTestContext()
        let receiptStore = InMemoryWatchCommandReceiptStore()
        let processor = WatchCommandProcessor(receiptStore: receiptStore)
        let taskID = UUID()
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: taskID,
            segmentID: nil,
            issuedAt: Date(timeIntervalSinceReferenceDate: 1_000),
            deviceID: "watch-test"
        )

        let missingResult = try processor.process(command, allowParallelTimers: true, context: context)
        let task = TaskNode(title: "Late task", parentID: nil, deviceID: "test")
        task.id = taskID
        context.insert(task)
        try context.save()
        let retryResult = try processor.process(command, allowParallelTimers: true, context: context)

        #expect(missingResult == .missingTask(taskID))
        #expect(retryResult.isProcessed)
        #expect(receiptStore.contains(command.id))
    }

    @Test @MainActor
    func watchStopCommandClosesSegmentAndDedupesRepeatedDelivery() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Stop from watch", parentID: nil, colorHex: nil, iconName: nil)
        let segment = try timeRepository.startTask(taskID: task.id, source: .watch)
        let receiptStore = InMemoryWatchCommandReceiptStore()
        let processor = WatchCommandProcessor(receiptStore: receiptStore)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: segment.id,
            issuedAt: Date(timeIntervalSinceReferenceDate: 1_100),
            deviceID: "watch-test"
        )

        let firstResult = try processor.process(command, allowParallelTimers: true, context: context)
        let duplicateResult = try processor.process(command, allowParallelTimers: true, context: context)

        let stopped = try #require(try timeRepository.allSegments().first)
        #expect(firstResult == .stopped(segment.id))
        #expect(duplicateResult == .duplicate(command.id))
        #expect(stopped.endedAt != nil)
    }
}
