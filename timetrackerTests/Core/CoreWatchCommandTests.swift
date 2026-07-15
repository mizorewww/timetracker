import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreWatchCommandTests {
    @Test @MainActor
    func incomingPhoneQueueSurvivesRestartAndRecoversFromCorruption() throws {
        let suiteName = "WatchIncomingCommandStoreTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let key = "incoming"
        let store = WatchIncomingCommandStore(defaults: defaults, key: key)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: UUID(),
            segmentID: nil,
            issuedAt: Date(timeIntervalSinceReferenceDate: 42),
            deviceID: "watch"
        )

        store.save([command])
        #expect(WatchIncomingCommandStore(defaults: defaults, key: key).load() == [command])

        store.save([])
        #expect(defaults.object(forKey: key) == nil)

        defaults.set(Data("not-json".utf8), forKey: key)
        #expect(store.load().isEmpty)
        #expect(defaults.object(forKey: key) == nil)

        let excessiveCommands = (0...WatchTransportLimits.maximumIncomingCommands).map { offset in
            WatchTimerCommand(
                id: UUID(),
                type: .startTask,
                taskID: UUID(),
                segmentID: nil,
                issuedAt: command.issuedAt.addingTimeInterval(TimeInterval(offset)),
                deviceID: "watch"
            )
        }
        defaults.set(try JSONEncoder().encode(excessiveCommands), forKey: key)
        #expect(store.load().isEmpty)
        #expect(defaults.object(forKey: key) == nil)

        var structurallyInvalid = command
        structurallyInvalid.deviceID = ""
        defaults.set(try JSONEncoder().encode([structurallyInvalid]), forKey: key)
        #expect(store.load().isEmpty)
        #expect(defaults.object(forKey: key) == nil)
    }

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

        var invalidCommand = command
        invalidCommand.deviceID = ""
        #expect(
            WatchConnectivityPayloadCodec.decodeCommand(
                from: WatchConnectivityPayloadCodec.encode(command: invalidCommand)
            ) == nil
        )
    }

    @Test
    func watchConnectivityPayloadCodecRoundTripsTypedCommandResults() throws {
        let result = WatchCommandResult(
            commandID: UUID(),
            status: .missingTask,
            completedAt: Date(timeIntervalSinceReferenceDate: 1_500),
            relatedID: UUID(),
            failureCode: "missing"
        )

        let payload = WatchConnectivityPayloadCodec.encode(result: result)
        let decoded = try #require(WatchConnectivityPayloadCodec.decodeCommandResult(from: payload))

        #expect(decoded == result)
        #expect(payload["received"] as? Bool == true)
        #expect(WatchConnectivityPayloadCodec.decodeCommand(from: payload) == nil)

        let oversizedFailure = WatchCommandResult.failed(
            commandID: UUID(),
            failureCode: String(
                repeating: "x",
                count: WatchTransportLimits.maximumFailureCodeBytes + 1
            )
        )
        #expect(
            WatchConnectivityPayloadCodec.decodeCommandResult(
                from: WatchConnectivityPayloadCodec.encode(result: oversizedFailure)
            ) == nil
        )
    }

    @Test
    func watchProcessingResultsMapToEveryTypedTerminalStatus() {
        let commandID = UUID()
        let relatedID = UUID()

        #expect(
            WatchCommandProcessingResult.started(relatedID)
                .terminalResult(commandID: commandID).status == .success
        )
        #expect(
            WatchCommandProcessingResult.stopped(relatedID)
                .terminalResult(commandID: commandID).status == .success
        )
        #expect(
            WatchCommandProcessingResult.duplicate(commandID)
                .terminalResult(commandID: commandID).status == .duplicate
        )
        #expect(
            WatchCommandProcessingResult.missingTask(relatedID)
                .terminalResult(commandID: commandID).status == .missingTask
        )
        #expect(
            WatchCommandProcessingResult.missingSegment(relatedID)
                .terminalResult(commandID: commandID).status == .missingSegment
        )
        #expect(
            WatchCommandProcessingResult.invalid
                .terminalResult(commandID: commandID).status == .invalid
        )
        #expect(WatchCommandResult.failed(commandID: commandID).status == .failed)
    }

    @Test
    func timedOutWatchCommandUnlocksAndRetriesWithTheSameIdempotencyKey() throws {
        let commandID = UUID()
        let originalIssueDate = Date(timeIntervalSinceReferenceDate: 100)
        let retryDate = Date(timeIntervalSinceReferenceDate: 200)
        let command = WatchTimerCommand(
            id: commandID,
            type: .startTask,
            taskID: UUID(),
            segmentID: nil,
            issuedAt: originalIssueDate,
            deviceID: "watch"
        )
        var queue = WatchCommandQueueState()
        queue.enqueue(command)

        let timeoutResult = queue.timeOut(commandID: commandID, completedAt: retryDate)
        let timeout = try #require(timeoutResult)

        #expect(timeout.status == .timeout)
        #expect(queue.pendingCommands.isEmpty)
        #expect(queue.failedCommands.first?.result.status == .timeout)

        let retryCommand = queue.retry(commandID: commandID, issuedAt: retryDate)
        let retry = try #require(retryCommand)

        #expect(retry.id == commandID)
        #expect(retry.issuedAt == retryDate)
        #expect(queue.failedCommands.isEmpty)
        #expect(queue.pendingCommands == [retry])

        _ = queue.resolve(
            WatchCommandResult(
                commandID: commandID,
                status: .duplicate,
                completedAt: retryDate.addingTimeInterval(1),
                relatedID: nil,
                failureCode: nil
            )
        )
        #expect(queue.pendingCommands.isEmpty)
        #expect(queue.failedCommands.isEmpty)
    }

    @Test
    func failedWatchCommandCanBeDiscardedAndLateSnapshotSuccessClearsTimeout() throws {
        let taskID = UUID()
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: taskID,
            segmentID: nil,
            issuedAt: Date(timeIntervalSinceReferenceDate: 300),
            deviceID: "watch"
        )
        var queue = WatchCommandQueueState()
        queue.enqueue(command)
        _ = queue.timeOut(commandID: command.id, completedAt: command.issuedAt.addingTimeInterval(20))

        let activeTimer = WatchActiveTimerSnapshot(
            id: UUID(),
            taskID: taskID,
            title: "Task",
            path: "",
            startedAt: command.issuedAt,
            colorHex: nil,
            iconName: nil
        )
        let confirmed = queue.confirmReflectedCommands(
            in: watchSnapshot(
                generatedAt: command.issuedAt.addingTimeInterval(21),
                activeTimers: [activeTimer]
            )
        )

        #expect(confirmed == Set([command.id]))
        #expect(queue.failedCommands.isEmpty)

        queue.enqueue(command)
        _ = queue.timeOut(commandID: command.id)
        queue.discard(commandID: command.id)
        #expect(queue.failedCommands.isEmpty)
    }

    @Test
    func watchCommandQueuePersistsPendingAndRetryableFailures() throws {
        let pending = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: UUID(),
            segmentID: nil,
            issuedAt: Date(timeIntervalSinceReferenceDate: 400),
            deviceID: "watch"
        )
        let failed = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: UUID(),
            issuedAt: Date(timeIntervalSinceReferenceDate: 500),
            deviceID: "watch"
        )
        var queue = WatchCommandQueueState()
        queue.enqueue(pending)
        queue.enqueue(failed)
        _ = queue.timeOut(commandID: failed.id, completedAt: failed.issuedAt.addingTimeInterval(20))

        let data = try JSONEncoder().encode(queue)
        let decoded = try JSONDecoder().decode(WatchCommandQueueState.self, from: data)

        #expect(decoded == queue)
        #expect(decoded.pendingCommands == [pending])
        #expect(decoded.failedCommands.map(\.command) == [failed])
    }

    @Test
    func watchCommandQueueBoundsPendingAndFailedRestorationState() {
        let issuedAt = Date(timeIntervalSinceReferenceDate: 600)
        var queue = WatchCommandQueueState()
        for offset in 0...WatchTransportLimits.maximumPersistedPendingCommands {
            queue.enqueue(
                WatchTimerCommand(
                    id: UUID(),
                    type: .startTask,
                    taskID: UUID(),
                    segmentID: nil,
                    issuedAt: issuedAt.addingTimeInterval(TimeInterval(offset)),
                    deviceID: "watch"
                )
            )
        }

        #expect(queue.pendingCommands.count == WatchTransportLimits.maximumPersistedPendingCommands)
        #expect(queue.failedCommands.count == 1)
        #expect(queue.failedCommands.first?.result.failureCode == "queueOverflow")
        #expect(queue.isSafeForRestoration)

        for command in queue.pendingCommands {
            _ = queue.resolve(
                WatchCommandResult(
                    commandID: command.id,
                    status: .invalid,
                    completedAt: issuedAt,
                    relatedID: nil,
                    failureCode: nil
                )
            )
        }

        #expect(queue.pendingCommands.isEmpty)
        #expect(queue.failedCommands.count == WatchTransportLimits.maximumPersistedFailedCommands)
        #expect(queue.isSafeForRestoration)
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
        #expect(snapshot.isValid(at: snapshot.generatedAt))

        var invalidSummary = snapshot
        invalidSummary.todayGrossSeconds = -1
        #expect(invalidSummary.isValid(at: invalidSummary.generatedAt) == false)
        #expect(
            WatchConnectivityPayloadCodec.decodeState(
                from: WatchConnectivityPayloadCodec.encode(state: invalidSummary)
            ) == nil
        )

        var oversizedTitle = snapshot
        oversizedTitle.activeTimers[0].title = String(
            repeating: "x",
            count: WatchTransportLimits.maximumTitleBytes + 1
        )
        #expect(oversizedTitle.isValid(at: oversizedTitle.generatedAt) == false)

        var futureSnapshot = snapshot
        futureSnapshot.generatedAt = snapshot.generatedAt.addingTimeInterval(
            WatchTransportLimits.maximumFutureClockSkew + 1
        )
        #expect(futureSnapshot.isValid(at: snapshot.generatedAt) == false)
    }

    @Test
    func watchSnapshotTransportBoundsAggregateTextAndPreservesUnicodePrefixes() {
        let original = String(repeating: "🧑🏽‍💻", count: 100)
        let bounded = WatchTransportLimits.boundedUTF8Prefix(
            original,
            maximumUTF8Bytes: 17
        )

        #expect(bounded.utf8.count <= 17)
        #expect(original.hasPrefix(bounded))
        #expect(String(data: Data(bounded.utf8), encoding: .utf8) == bounded)

        let generatedAt = Date(timeIntervalSinceReferenceDate: 2_500)
        let recentTasks = (0..<WatchTransportLimits.maximumRecentTasks).map { _ in
            WatchRecentTaskSnapshot(
                taskID: UUID(),
                title: String(
                    repeating: "t",
                    count: WatchTransportLimits.maximumProjectedTitleBytes
                ),
                path: String(
                    repeating: "p",
                    count: WatchTransportLimits.maximumProjectedPathBytes
                ),
                colorHex: nil,
                iconName: nil
            )
        }
        let snapshot = WatchStateSnapshot(
            generatedAt: generatedAt,
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            activeTimers: [],
            recentTasks: recentTasks
        )

        #expect(recentTasks.allSatisfy { $0.isStructurallyValid })
        #expect(snapshot.isValid(at: generatedAt) == false)
    }

    @Test
    func watchStartCommandWaitsForANewerSnapshotContainingTheTask() {
        let taskID = UUID()
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: taskID,
            segmentID: nil,
            issuedAt: issuedAt,
            deviceID: "watch"
        )
        let activeTimer = WatchActiveTimerSnapshot(
            id: UUID(),
            taskID: taskID,
            title: "Task",
            path: "",
            startedAt: issuedAt,
            colorHex: nil,
            iconName: nil
        )

        #expect(command.isReflected(in: watchSnapshot(generatedAt: issuedAt.addingTimeInterval(-1), activeTimers: [activeTimer])) == false)
        #expect(command.isReflected(in: watchSnapshot(generatedAt: issuedAt.addingTimeInterval(1), activeTimers: [])) == false)
        #expect(command.isReflected(in: watchSnapshot(generatedAt: issuedAt.addingTimeInterval(1), activeTimers: [activeTimer])))
    }

    @Test
    func watchStopCommandWaitsForANewerSnapshotWithoutTheSegment() {
        let segmentID = UUID()
        let issuedAt = Date(timeIntervalSinceReferenceDate: 2_000)
        let activeTimer = WatchActiveTimerSnapshot(
            id: segmentID,
            taskID: UUID(),
            title: "Task",
            path: "",
            startedAt: issuedAt.addingTimeInterval(-100),
            colorHex: nil,
            iconName: nil
        )
        let command = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: segmentID,
            issuedAt: issuedAt,
            deviceID: "watch"
        )

        #expect(command.isReflected(in: watchSnapshot(generatedAt: issuedAt.addingTimeInterval(-1), activeTimers: [])) == false)
        #expect(command.isReflected(in: watchSnapshot(generatedAt: issuedAt.addingTimeInterval(1), activeTimers: [activeTimer])) == false)
        #expect(command.isReflected(in: watchSnapshot(generatedAt: issuedAt.addingTimeInterval(1), activeTimers: [])))
    }

    @Test
    func watchSnapshotFreshnessUsesTheSharedFifteenMinuteBoundary() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 3_000)
        let snapshot = watchSnapshot(generatedAt: generatedAt, activeTimers: [])

        #expect(snapshot.freshness(at: generatedAt.addingTimeInterval(WatchStateSnapshot.staleAfter)) == .current)
        #expect(snapshot.freshness(at: generatedAt.addingTimeInterval(WatchStateSnapshot.staleAfter + 1)) == .stale)
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
    func watchSnapshotRecencyPreventsOutOfOrderStateRegression() {
        let current = watchSnapshot(
            generatedAt: Date(timeIntervalSinceReferenceDate: 200),
            activeTimers: []
        )
        let older = watchSnapshot(
            generatedAt: Date(timeIntervalSinceReferenceDate: 100),
            activeTimers: []
        )
        let sameGeneration = watchSnapshot(
            generatedAt: current.generatedAt,
            activeTimers: []
        )

        #expect(older.isAtLeastAsRecent(as: current) == false)
        #expect(current.isAtLeastAsRecent(as: older))
        #expect(sameGeneration.isAtLeastAsRecent(as: current))
    }

    @Test
    func watchDashboardUsesASingleGlanceableCrownScrollableLayout() throws {
        let source = try [
            "timetrackerWatchApp/WatchDashboardView.swift",
            "timetrackerWatchApp/WatchTaskListView.swift",
            "timetrackerWatchApp/WatchTimerRows.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(source.contains("NavigationStack"))
        #expect(source.contains("List {"))
        #expect(source.contains("WatchActiveTimerRow"))
        #expect(source.contains("WatchTaskShortcutRow"))
        #expect(source.contains("quickStartTaskLimit = 4"))
        #expect(source.contains("inactiveTasks.prefix(Self.quickStartTaskLimit)"))
        #expect(source.contains("NavigationLink"))
        #expect(source.contains("WatchTaskListView"))
        #expect(source.contains("minHeight: 44"))
        #expect(source.contains("if !hasReceivedSnapshot, let status"))
        #expect(source.contains("isReachable && !hasConnectivityError ? .sending : .queued"))
        #expect(!source.contains("return .offline"))
        #expect(source.contains(".privacySensitive()"))
        #expect(source.contains("\\.isLuminanceReduced"))
        #expect(!source.contains("TabView"))
        #expect(!source.contains("TimelineView"))
        #expect(!source.contains("handGestureShortcut"))
    }

    @Test
    func watchStoreReleasesTimedOutRowsAndOffersRetryAndDiscard() throws {
        let storeFiles = [
            "timetrackerWatchApp/WatchAppStore.swift",
            "timetrackerWatchApp/WatchAppStore+Commands.swift",
            "timetrackerWatchApp/WatchAppStore+Connectivity.swift"
        ]
        let source = try storeFiles.map(sourceText).joined(separator: "\n")
        let dashboard = try [
            "timetrackerWatchApp/WatchDashboardView.swift",
            "timetrackerWatchApp/WatchStatusViews.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(source.contains("commandQueue.enqueue(command)"))
        #expect(source.contains("commandQueue.timeOut(commandID:"))
        #expect(source.contains("func retryCommand(commandID:"))
        #expect(source.contains("func discardCommand(commandID:"))
        #expect(source.contains("decodeCommandResult"))
        #expect(source.contains("session.transferUserInfo(payload)"))
        #expect(source.contains("scheduleConfirmationTimeout"))
        #expect(source.contains("confirmationTasks[commandID]?.cancel()"))
        #expect(source.contains("confirmationTasks[commandID] = nil"))
        #expect(source.contains("scheduleSnapshotFreshness"))
        #expect(source.contains("state.isAtLeastAsRecent(as: snapshot)"))
        #expect(source.contains("hasReceivedSnapshot = true"))
        #expect(source.contains("recordConnectivityError"))
        #expect(source.contains("deinit {"))
        #expect(source.contains("for task in confirmationTasks.values"))
        #expect(source.contains("snapshotFreshnessTask?.cancel()"))
        #expect(source.contains("WatchTransportLimits.maximumQueueEncodedBytes"))
        #expect(source.contains("restoredQueue.isSafeForRestoration"))
        #expect(source.contains("commandQueue.isSafeForRestoration"))
        #expect(!source.contains("unconfirmedCommandIDs"))
        for fileName in storeFiles {
            let lineCount = try sourceText(fileName)
                .split(separator: "\n", omittingEmptySubsequences: false)
                .count
            #expect(lineCount <= 180, "\(fileName) has \(lineCount) lines")
        }
        #expect(dashboard.contains("WatchCommandFailureRow"))
        #expect(dashboard.contains("watch.command.retry"))
        #expect(dashboard.contains("watch.command.discard"))
    }

    @Test
    func watchConnectivityBridgeDeclaresApplicationContextAndQueuedCommandHandling() throws {
        let source = try sourceText("timetracker/Services/SystemIntegration/WatchConnectivityBridge.swift")

        #expect(source.contains("updateApplicationContext"))
        #expect(source.contains("didReceiveUserInfo"))
        #expect(source.contains("didReceiveMessage"))
        #expect(source.contains("WatchConnectivityPayloadCodec.decodeCommand"))
        #expect(source.contains("WatchConnectivityPayloadCodec.encode(result:"))
        #expect(source.contains("deliverDurableCommandResult"))
        #expect(source.contains("(WatchTimerCommand) -> WatchCommandResult"))
        #expect(source.contains("WatchConnectivityDeliveryStatus"))
        #expect(source.contains("diagnosticHandler"))
        #expect(source.contains("errorHandler:"))
        #expect(source.contains("recordFailure(operation: .activation"))
        #expect(!source.contains("try? session.updateApplicationContext"))
    }

    @Test
    func watchConnectivityFailureStatusPreservesItsDiagnosticMessage() {
        let status = WatchConnectivityDeliveryStatus.failed("transport failed")

        #expect(status == .failed("transport failed"))
        #expect(status != .submitted)
    }

    @Test
    func storeRefreshPublishesWatchStateWhenLedgerOrTasksChange() throws {
        let source = try sourceText("timetracker/Stores/Refresh/StoreRefreshCoordinator.swift")
        let facade = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+WatchSnapshot.swift")

        #expect(source.contains("syncWatchSnapshotIfAvailable"))
        #expect(facade.contains("watchTaskShortcuts()"))
        #expect(facade.contains("preferences.quickStartTaskIDs"))
        #expect(facade.contains("prefix(WatchTransportLimits.maximumRecentTasks)"))
        #expect(facade.contains("maximumSnapshotTextBytes"))
        #expect(facade.contains("boundedUTF8Prefix"))
        #expect(facade.contains("WatchConnectivityBridge.shared.updateApplicationContext"))
    }

    @Test
    func appActivatesWatchBridgeAndWeakSceneRouterRoutesIncomingCommands() throws {
        let app = try sourceText("timetracker/App/timetrackerApp.swift")
        let contentView = try sourceText("timetracker/App/ContentView.swift")
        let router = try sourceText("timetracker/App/WatchCommandRouter.swift")
        let facade = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+WatchSnapshot.swift")

        #expect(app.contains("WatchConnectivityBridge.shared.activateIfSupported"))
        #expect(contentView.contains("WatchCommandRouter.shared.register"))
        #expect(contentView.contains("WatchCommandRouter.shared.unregister"))
        #expect(!contentView.contains("WatchConnectivityBridge.shared.commandHandler"))
        #expect(router.contains("weak var value: TimeTrackerStore?"))
        #expect(router.contains("[weak self] command"))
        #expect(router.contains("WatchConnectivityBridge.shared.commandHandler = nil"))
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
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: task.id,
            segmentID: nil,
            issuedAt: issuedAt,
            deviceID: "watch-test"
        )

        let firstResult = try processor.process(
            command,
            allowParallelTimers: true,
            context: context,
            now: issuedAt
        )
        try SystemActionCommandHandler().stopTimer(taskID: task.id, context: context)
        let duplicateResult = try processor.process(
            command,
            allowParallelTimers: true,
            context: context,
            now: issuedAt.addingTimeInterval(WatchTransportLimits.maximumCommandAge + 1)
        )

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
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1_000)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: taskID,
            segmentID: nil,
            issuedAt: issuedAt,
            deviceID: "watch-test"
        )

        let missingResult = try processor.process(
            command,
            allowParallelTimers: true,
            context: context,
            now: issuedAt
        )
        let task = TaskNode(title: "Late task", parentID: nil, deviceID: "test")
        task.id = taskID
        context.insert(task)
        try context.save()
        let retryResult = try processor.process(
            command,
            allowParallelTimers: true,
            context: context,
            now: issuedAt.addingTimeInterval(1)
        )

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
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1_100)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: segment.id,
            issuedAt: issuedAt,
            deviceID: "watch-test"
        )

        let firstResult = try processor.process(
            command,
            allowParallelTimers: true,
            context: context,
            now: issuedAt
        )
        let duplicateResult = try processor.process(
            command,
            allowParallelTimers: true,
            context: context,
            now: issuedAt.addingTimeInterval(WatchTransportLimits.maximumCommandAge + 1)
        )

        let stopped = try #require(try timeRepository.allSegments().first)
        #expect(firstResult == .stopped(segment.id))
        #expect(duplicateResult == .duplicate(command.id))
        #expect(stopped.endedAt != nil)
    }

    @Test @MainActor
    func staleWatchCommandCannotMutateLedgerAndCanBeExplicitlyRetried() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Delayed Watch command",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let receiptStore = InMemoryWatchCommandReceiptStore()
        let processor = WatchCommandProcessor(receiptStore: receiptStore)
        let commandID = UUID()
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1_200)
        let staleCommand = WatchTimerCommand(
            id: commandID,
            type: .startTask,
            taskID: task.id,
            segmentID: nil,
            issuedAt: issuedAt,
            deviceID: "watch-test"
        )
        let retryDate = issuedAt.addingTimeInterval(WatchTransportLimits.maximumCommandAge + 1)

        let staleResult = try processor.process(
            staleCommand,
            allowParallelTimers: true,
            context: context,
            now: retryDate
        )

        #expect(staleResult == .invalid)
        #expect(try timeRepository.activeSegments().isEmpty)
        #expect(receiptStore.contains(commandID) == false)

        var retriedCommand = staleCommand
        retriedCommand.issuedAt = retryDate
        let retryResult = try processor.process(
            retriedCommand,
            allowParallelTimers: true,
            context: context,
            now: retryDate
        )

        #expect(retryResult.isProcessed)
        #expect(try timeRepository.activeSegments().count == 1)
        #expect(receiptStore.contains(commandID))
    }

    @Test @MainActor
    func watchStopClipsExpiredPomodoroToPersistedDeadline() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pomodoroRepository = SwiftDataPomodoroRepository(
            context: context,
            timeRepository: timeRepository,
            deviceID: "test"
        )
        let task = try taskRepository.createTask(
            title: "Expired Watch focus",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let run = try pomodoroRepository.startPomodoro(
            taskID: task.id,
            focusSeconds: 60,
            breakSeconds: 30,
            targetRounds: 1
        )
        let sessionID = try #require(run.sessionID)
        let segment = try #require(try timeRepository.activeSegments().first { $0.sessionID == sessionID })
        let session = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        let phaseStartedAt = Date().addingTimeInterval(-120)
        let deadline = phaseStartedAt.addingTimeInterval(60)
        run.startedAt = phaseStartedAt
        segment.startedAt = phaseStartedAt
        session.startedAt = phaseStartedAt
        try context.save()
        let receiptStore = InMemoryWatchCommandReceiptStore()
        let processor = WatchCommandProcessor(receiptStore: receiptStore)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: segment.id,
            issuedAt: Date(),
            deviceID: "watch-test"
        )

        let result = try processor.process(command, allowParallelTimers: true, context: context)

        let persistedRun = try #require(try pomodoroRepository.runs().first { $0.id == run.id })
        let persistedSegment = try #require(try timeRepository.allSegments().first { $0.id == segment.id })
        let persistedSession = try #require(try timeRepository.sessions().first { $0.id == sessionID })
        #expect(result == .stopped(segment.id))
        #expect(persistedRun.state == .completed)
        #expect(persistedRun.endedAt == deadline)
        #expect(persistedSegment.endedAt == deadline)
        #expect(persistedSession.endedAt == deadline)
    }

    @Test @MainActor
    func watchStoreRecordsTheCommittedTimerInTheConflictSnapshot() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Watch snapshot task",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        try withWatchCloudSyncMode {
            let stateURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("TimeTrackerWatchSnapshot-\(UUID().uuidString)", isDirectory: true)
                .appendingPathComponent("state.json")
            let service = SyncConflictService(stateURL: stateURL)
            #expect(try service.bootstrap(context: context) == nil)
            let baselineExportID = UUID()
            try service.markCloudExportStarted(eventID: baselineExportID)
            try service.markCloudExportFinished(eventID: baselineExportID, succeeded: true)
            let command = WatchTimerCommand(
                id: UUID(),
                type: .startTask,
                taskID: task.id,
                segmentID: nil,
                issuedAt: Date(),
                deviceID: "watch-test"
            )

            store.handleWatchCommand(command, recordingWith: service)

            let segment = try #require(store.activeSegment(for: task.id))
            let stateJSON = try String(contentsOf: stateURL, encoding: .utf8)
            #expect(stateJSON.contains(segment.id.uuidString))
        }
    }
}

@MainActor
private func withWatchCloudSyncMode(_ body: () throws -> Void) throws {
    let defaults = UserDefaults.standard
    let previousMode = defaults.object(forKey: AppCloudSync.modeKey)
    let previousUploadReset = defaults.object(forKey: AppCloudSync.pendingCloudUploadResetKey)
    let previousDownloadReset = defaults.object(forKey: AppCloudSync.pendingCloudDownloadResetKey)
    defaults.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
    defaults.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
    defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
    defer {
        if let previousMode {
            defaults.set(previousMode, forKey: AppCloudSync.modeKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.modeKey)
        }
        if let previousUploadReset {
            defaults.set(previousUploadReset, forKey: AppCloudSync.pendingCloudUploadResetKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
        }
        if let previousDownloadReset {
            defaults.set(previousDownloadReset, forKey: AppCloudSync.pendingCloudDownloadResetKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
        }
    }
    try body()
}

private func watchSnapshot(
    generatedAt: Date,
    activeTimers: [WatchActiveTimerSnapshot]
) -> WatchStateSnapshot {
    WatchStateSnapshot(
        generatedAt: generatedAt,
        todayGrossSeconds: 0,
        todayWallSeconds: 0,
        activeTimers: activeTimers,
        recentTasks: []
    )
}
