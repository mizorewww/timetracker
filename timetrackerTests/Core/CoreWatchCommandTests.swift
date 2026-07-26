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

        let excessiveCommands = (0 ... WatchTransportLimits.maximumIncomingCommands).map { offset in
            WatchTimerCommand(
                id: UUID(),
                type: .startTask,
                taskID: UUID(),
                segmentID: nil,
                issuedAt: command.issuedAt.addingTimeInterval(TimeInterval(offset)),
                deviceID: "watch"
            )
        }
        try defaults.set(JSONEncoder().encode(excessiveCommands), forKey: key)
        #expect(store.load().isEmpty)
        #expect(defaults.object(forKey: key) == nil)

        var structurallyInvalid = command
        structurallyInvalid.deviceID = ""
        try defaults.set(JSONEncoder().encode([structurallyInvalid]), forKey: key)
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
            issuedAt: Date(timeIntervalSinceReferenceDate: 1234),
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
            completedAt: Date(timeIntervalSinceReferenceDate: 1500),
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
    func watchCommandQueueRejectsEquivalentActionsWithDifferentIdempotencyKeys() throws {
        let taskID = UUID()
        let issuedAt = Date(timeIntervalSinceReferenceDate: 250)
        let original = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: taskID,
            segmentID: nil,
            issuedAt: issuedAt,
            deviceID: "watch"
        )
        var duplicate = original
        duplicate.id = UUID()
        duplicate.issuedAt = issuedAt.addingTimeInterval(1)
        var reusedKey = original
        reusedKey.type = .stopSegment
        reusedKey.taskID = nil
        reusedKey.segmentID = UUID()
        let distinct = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: UUID(),
            segmentID: nil,
            issuedAt: issuedAt,
            deviceID: "watch"
        )
        var queue = WatchCommandQueueState()

        let acceptedOriginal = queue.enqueue(original)
        let acceptedDuplicate = queue.enqueue(duplicate)
        let acceptedReusedKey = queue.enqueue(reusedKey)
        let acceptedDistinct = queue.enqueue(distinct)
        #expect(acceptedOriginal)
        #expect(acceptedDuplicate == false)
        #expect(acceptedReusedKey == false)
        #expect(acceptedDistinct)
        #expect(queue.pendingCommands == [original, distinct])

        let unsafePayload = WatchCommandQueueFixture(
            pendingCommands: [original, duplicate],
            failedCommands: []
        )
        let restoredQueue = try JSONDecoder().decode(
            WatchCommandQueueState.self,
            from: JSONEncoder().encode(unsafePayload)
        )
        #expect(restoredQueue.isSafeForRestoration == false)

        _ = queue.timeOut(commandID: original.id, completedAt: issuedAt.addingTimeInterval(20))
        let acceptedAfterFailure = queue.enqueue(duplicate)
        #expect(acceptedAfterFailure == false)
        let retryCommand = queue.retry(
            commandID: original.id,
            issuedAt: issuedAt.addingTimeInterval(21)
        )
        let retry = try #require(retryCommand)
        #expect(retry.id == original.id)
        #expect(queue.failedCommands.isEmpty)
        #expect(queue.pendingCommands == [distinct, retry])
    }

    @Test
    func failedWatchCommandCanBeDiscardedAndLateSnapshotSuccessClearsTimeout() {
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
        for offset in 0 ... WatchTransportLimits.maximumPersistedPendingCommands {
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
            generatedAt: Date(timeIntervalSinceReferenceDate: 2000),
            todayGrossSeconds: 3600,
            todayWallSeconds: 2400,
            activeTimers: [
                WatchActiveTimerSnapshot(
                    id: timerID,
                    taskID: taskID,
                    title: "Watch timer",
                    path: "Work",
                    startedAt: Date(timeIntervalSinceReferenceDate: 1900),
                    colorHex: "#0A84FF",
                    iconName: "timer"
                ),
            ],
            recentTasks: [
                WatchRecentTaskSnapshot(
                    taskID: taskID,
                    title: "Continue",
                    path: "Work",
                    colorHex: "#0A84FF",
                    iconName: "bolt",
                    quickStartRank: 0,
                    allTasksRank: 0
                ),
            ]
        )

        let payload = WatchConnectivityPayloadCodec.encode(state: snapshot)
        let decoded = try #require(WatchConnectivityPayloadCodec.decodeState(from: payload))

        #expect(decoded == snapshot)
        #expect(snapshot.isValid(at: snapshot.generatedAt))
        #expect(
            (payload["recentTasks"] as? [[String: Any]])?.first?["quickStartRank"] as? Int == 0
        )
        #expect(
            (payload["recentTasks"] as? [[String: Any]])?.first?["allTasksRank"] as? Int == 0
        )

        var legacyPayload = payload
        var legacyTasks = try #require(
            legacyPayload["recentTasks"] as? [[String: Any]]
        )
        legacyTasks[0].removeValue(forKey: "quickStartRank")
        legacyTasks[0].removeValue(forKey: "allTasksRank")
        legacyPayload["recentTasks"] = legacyTasks
        let legacySnapshot = try #require(
            WatchConnectivityPayloadCodec.decodeState(from: legacyPayload)
        )
        #expect(legacySnapshot.recentTasks.first?.quickStartRank == nil)
        #expect(legacySnapshot.recentTasks.first?.allTasksRank == nil)
        #expect(legacySnapshot.allTasksByUsage == legacySnapshot.recentTasks)

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

        var duplicateRanks = snapshot
        duplicateRanks.recentTasks.append(
            WatchRecentTaskSnapshot(
                taskID: UUID(),
                title: "Duplicate rank",
                path: "",
                colorHex: nil,
                iconName: nil,
                quickStartRank: 0
            )
        )
        #expect(duplicateRanks.isValid(at: snapshot.generatedAt) == false)
        #expect(
            WatchConnectivityPayloadCodec.decodeState(
                from: WatchConnectivityPayloadCodec.encode(state: duplicateRanks)
            ) == nil
        )

        var duplicateAllTasksRanks = snapshot
        duplicateAllTasksRanks.recentTasks.append(
            WatchRecentTaskSnapshot(
                taskID: UUID(),
                title: "Duplicate all-tasks rank",
                path: "",
                colorHex: nil,
                iconName: nil,
                allTasksRank: 0
            )
        )
        #expect(duplicateAllTasksRanks.isValid(at: snapshot.generatedAt) == false)
        #expect(
            WatchConnectivityPayloadCodec.decodeState(
                from: WatchConnectivityPayloadCodec.encode(
                    state: duplicateAllTasksRanks
                )
            ) == nil
        )

        var reversedAllTasksRanks = snapshot
        reversedAllTasksRanks.recentTasks[0].allTasksRank = 1
        let reorderedTaskID = UUID()
        reversedAllTasksRanks.recentTasks.append(
            WatchRecentTaskSnapshot(
                taskID: reorderedTaskID,
                title: "First by all-tasks rank",
                path: "",
                colorHex: nil,
                iconName: nil,
                allTasksRank: 0
            )
        )
        #expect(reversedAllTasksRanks.isValid(at: snapshot.generatedAt))
        #expect(reversedAllTasksRanks.allTasksByUsage.first?.taskID == reorderedTaskID)

        var partialAllTasksRanks = snapshot
        partialAllTasksRanks.recentTasks.append(
            WatchRecentTaskSnapshot(
                taskID: UUID(),
                title: "Missing all-tasks rank",
                path: "",
                colorHex: nil,
                iconName: nil
            )
        )
        #expect(partialAllTasksRanks.isValid(at: snapshot.generatedAt) == false)
        #expect(
            WatchConnectivityPayloadCodec.decodeState(
                from: WatchConnectivityPayloadCodec.encode(state: partialAllTasksRanks)
            ) == nil
        )

        var gappedAllTasksRanks = snapshot
        gappedAllTasksRanks.recentTasks.append(
            WatchRecentTaskSnapshot(
                taskID: UUID(),
                title: "Gapped all-tasks rank",
                path: "",
                colorHex: nil,
                iconName: nil,
                allTasksRank: 2
            )
        )
        #expect(gappedAllTasksRanks.isValid(at: snapshot.generatedAt) == false)
        #expect(
            WatchConnectivityPayloadCodec.decodeState(
                from: WatchConnectivityPayloadCodec.encode(state: gappedAllTasksRanks)
            ) == nil
        )

        var outOfRangeRank = snapshot
        outOfRangeRank.recentTasks[0].quickStartRank =
            WatchTransportLimits.maximumQuickStartTasks
        #expect(outOfRangeRank.isValid(at: snapshot.generatedAt) == false)
        #expect(
            WatchConnectivityPayloadCodec.decodeState(
                from: WatchConnectivityPayloadCodec.encode(state: outOfRangeRank)
            ) == nil
        )

        outOfRangeRank = snapshot
        outOfRangeRank.recentTasks[0].allTasksRank =
            WatchTransportLimits.maximumRecentTasks
        #expect(outOfRangeRank.isValid(at: snapshot.generatedAt) == false)
        #expect(
            WatchConnectivityPayloadCodec.decodeState(
                from: WatchConnectivityPayloadCodec.encode(state: outOfRangeRank)
            ) == nil
        )
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

        let generatedAt = Date(timeIntervalSinceReferenceDate: 2500)
        let recentTasks = (0 ..< WatchTransportLimits.maximumRecentTasks).map { _ in
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
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1000)
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
        let issuedAt = Date(timeIntervalSinceReferenceDate: 2000)
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
        let generatedAt = Date(timeIntervalSinceReferenceDate: 3000)
        let snapshot = watchSnapshot(generatedAt: generatedAt, activeTimers: [])

        #expect(snapshot.freshness(at: generatedAt.addingTimeInterval(WatchStateSnapshot.staleAfter)) == .current)
        #expect(snapshot.freshness(at: generatedAt.addingTimeInterval(WatchStateSnapshot.staleAfter + 1)) == .stale)
    }

    @Test
    func staleWatchSnapshotFreezesElapsedTimeAtTheSnapshotBoundary() {
        let generatedAt = Date(timeIntervalSinceReferenceDate: 3000)
        let timer = WatchActiveTimerSnapshot(
            id: UUID(),
            taskID: UUID(),
            title: "Focus",
            path: "",
            startedAt: generatedAt.addingTimeInterval(-30 * 60),
            colorHex: nil,
            iconName: nil
        )

        #expect(timer.elapsedPresentation(
            for: .stale,
            generatedAt: generatedAt
        ) == .frozen(seconds: 30 * 60))
        #expect(timer.elapsedPresentation(
            for: .current,
            generatedAt: generatedAt
        ) == .live(startedAt: timer.startedAt))
    }

    @Test @MainActor
    func watchSnapshotRanksAllTasksByUsageAndKeepsQuickStartMetadata() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let pinned = try taskRepository.createTask(title: "Pinned", parentID: nil, colorHex: "#0A84FF", iconName: "pin")
        let frequent = try taskRepository.createTask(title: "Frequent", parentID: nil, colorHex: "#30D158", iconName: "bolt")
        let occasional = try taskRepository.createTask(title: "Occasional", parentID: nil, colorHex: "#FF9F0A", iconName: "book")
        let start = Date(timeIntervalSinceReferenceDate: 5000)

        _ = try timeRepository.addManualSegment(
            taskID: occasional.id,
            startedAt: start,
            endedAt: start.addingTimeInterval(600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequent.id,
            startedAt: start.addingTimeInterval(1000),
            endedAt: start.addingTimeInterval(1600),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequent.id,
            startedAt: start.addingTimeInterval(2000),
            endedAt: start.addingTimeInterval(2600),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.setQuickStartTaskIDs([pinned.id])

        let snapshot = store.watchStateSnapshot(now: start.addingTimeInterval(3000))

        #expect(
            Array(snapshot.allTasksByUsage.map(\.taskID).prefix(3)) ==
                [frequent.id, occasional.id, pinned.id]
        )
        #expect(snapshot.recentTasks.first?.taskID == pinned.id)
        let pinnedSnapshot = try #require(
            snapshot.recentTasks.first { $0.taskID == pinned.id }
        )
        #expect(pinnedSnapshot.quickStartRank == 0)
        #expect(pinnedSnapshot.title == "Pinned")
        #expect(pinnedSnapshot.iconName == "pin")
    }

    @Test @MainActor
    func watchSnapshotIncludesEveryAvailableTaskWithoutPinsChangingAllTaskOrder() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        var createdTasks: [TaskNode] = []

        for index in 0 ..< 12 {
            try createdTasks.append(
                taskRepository.createTask(
                    title: "Task \(index)",
                    parentID: nil,
                    colorHex: nil,
                    iconName: nil
                )
            )
        }

        let archivedTask = createdTasks[11]
        archivedTask.statusRaw = LegacyTaskStatusRaw.archived
        let deletedTask = createdTasks[10]
        deletedTask.deletedAt = Date(timeIntervalSinceReferenceDate: 10)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.setQuickStartTaskIDs([createdTasks[7].id, createdTasks[2].id])

        let snapshot = store.watchStateSnapshot(now: Date(timeIntervalSinceReferenceDate: 20))

        #expect(snapshot.recentTasks.count == 10)
        #expect(
            snapshot.recentTasks.first { $0.taskID == createdTasks[7].id }?.quickStartRank == 0
        )
        #expect(
            snapshot.recentTasks.first { $0.taskID == createdTasks[2].id }?.quickStartRank == 1
        )
        #expect(
            Array(snapshot.recentTasks.map(\.taskID).prefix(2)) ==
                [createdTasks[7].id, createdTasks[2].id]
        )
        #expect(!snapshot.recentTasks.map(\.taskID).contains(archivedTask.id))
        #expect(!snapshot.recentTasks.map(\.taskID).contains(deletedTask.id))
    }

    @Test @MainActor
    func watchSnapshotExcludesAppleHealthSyncOnlyBranchesEvenWhenPinned() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let runningID = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        ).id
        let sleepID = AppleHealthTaskCatalog.taskDefinition(for: .sleep).id
        let ordinaryTask = try taskRepository.createTask(
            title: "Ordinary",
            parentID: nil
        )
        let runningTask = TaskNode(
            title: "Running",
            parentID: nil,
            deviceID: "health"
        )
        runningTask.id = runningID
        let runningChild = TaskNode(
            title: "Intervals",
            parentID: runningTask.id,
            deviceID: "health"
        )
        let sleepTask = TaskNode(
            title: "Sleep",
            parentID: nil,
            deviceID: "health"
        )
        sleepTask.id = sleepID
        context.insert(runningTask)
        context.insert(runningChild)
        context.insert(sleepTask)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.setQuickStartTaskIDs([
            runningTask.id,
            runningChild.id,
            sleepTask.id,
            ordinaryTask.id,
        ]))

        let snapshot = store.watchStateSnapshot(
            now: Date(timeIntervalSinceReferenceDate: 20)
        )

        #expect(snapshot.recentTasks.map(\.taskID) == [ordinaryTask.id])
        #expect(snapshot.allTasksByUsage.map(\.taskID) == [ordinaryTask.id])
        #expect(snapshot.recentTasks.first?.quickStartRank == 0)
    }

    @Test @MainActor
    func watchSnapshotBreaksUsageTiesByRecencyThenStableIdentity() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let olderFirstID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000001")
        )
        let olderSecondID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000002")
        )
        let recentID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000003")
        )
        let olderSecond = try taskRepository.createTask(
            proposedID: olderSecondID,
            title: "A title must not override stable identity",
            parentID: nil
        )
        let recent = try taskRepository.createTask(
            proposedID: recentID,
            title: "Recent",
            parentID: nil
        )
        let olderFirst = try taskRepository.createTask(
            proposedID: olderFirstID,
            title: "Z title must not override stable identity",
            parentID: nil
        )
        let olderStart = Date(timeIntervalSinceReferenceDate: 1000)
        let recentStart = olderStart.addingTimeInterval(300)

        for task in [olderSecond, olderFirst] {
            _ = try timeRepository.addManualSegment(
                taskID: task.id,
                startedAt: olderStart,
                endedAt: olderStart.addingTimeInterval(60),
                note: nil
            )
        }
        _ = try timeRepository.addManualSegment(
            taskID: recent.id,
            startedAt: recentStart,
            endedAt: recentStart.addingTimeInterval(60),
            note: nil
        )

        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        #expect(
            store.watchStateSnapshot(
                now: recentStart.addingTimeInterval(120)
            ).allTasksByUsage.map(\.taskID) ==
                [recentID, olderFirstID, olderSecondID]
        )
    }

    @Test @MainActor
    func watchSnapshotReservesTransportCapacityForPinnedQuickStartTasks() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let fixedUpdatedAt = Date(timeIntervalSinceReferenceDate: 1000)
        var createdTasks: [TaskNode] = []
        for index in 0 ..< (WatchTransportLimits.maximumRecentTasks + 4) {
            let taskID = try #require(
                UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012X",
                        index + 1
                    )
                )
            )
            let task = try taskRepository.createTask(
                proposedID: taskID,
                title: "Task",
                parentID: nil
            )
            task.updatedAt = fixedUpdatedAt
            createdTasks.append(task)
        }
        let pinnedTask = try #require(createdTasks.last)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        store.setQuickStartTaskIDs([pinnedTask.id])

        let snapshot = store.watchStateSnapshot(
            now: Date(timeIntervalSinceReferenceDate: 10000)
        )

        #expect(snapshot.recentTasks.count == WatchTransportLimits.maximumRecentTasks)
        #expect(
            snapshot.recentTasks.first { $0.taskID == pinnedTask.id }?.quickStartRank == 0
        )
        #expect(snapshot.recentTasks.first?.taskID == pinnedTask.id)
        #expect(snapshot.allTasksByUsage.last?.taskID == pinnedTask.id)
        #expect(
            snapshot.allTasksByUsage.map(\.taskID) ==
                Array(
                    createdTasks
                        .prefix(WatchTransportLimits.maximumRecentTasks - 1)
                        .map(\.id)
                ) + [pinnedTask.id]
        )
    }

    @Test @MainActor
    func watchSnapshotPreservesLegacyQuickStartPreviewAtCapacity() throws {
        let context = try makeTestContext()
        let baselineDate = Date(timeIntervalSinceReferenceDate: 1000)
        var taskIDs: [UUID] = []

        for index in 1 ... (WatchTransportLimits.maximumRecentTasks + 4) {
            let taskID = try #require(
                UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012X",
                        index
                    )
                )
            )
            taskIDs.append(taskID)
            let task = TaskNode(
                title: "Task",
                parentID: nil,
                deviceID: "fixture"
            )
            task.id = taskID
            task.updatedAt = index > WatchTransportLimits.maximumRecentTasks
                ? baselineDate.addingTimeInterval(TimeInterval(index))
                : baselineDate
            context.insert(task)
        }
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let snapshot = store.watchStateSnapshot(
            now: baselineDate.addingTimeInterval(1000)
        )
        let expectedLegacyPreview = Array(taskIDs.suffix(4).reversed())
        let expectedUsageMembership =
            Array(taskIDs.prefix(WatchTransportLimits.maximumRecentTasks - 4)) +
            Array(taskIDs.suffix(4))

        #expect(snapshot.recentTasks.count == WatchTransportLimits.maximumRecentTasks)
        #expect(
            Array(
                snapshot.recentTasks
                    .prefix(WatchTransportLimits.legacyQuickStartTaskLimit)
                    .map(\.taskID)
            ) == expectedLegacyPreview
        )
        #expect(
            snapshot.allTasksByUsage.map(\.taskID) == expectedUsageMembership
        )
    }

    @Test @MainActor
    func watchSnapshotReservesTransportCapacityForRunningTasks() throws {
        let context = try makeTestContext()
        let now = Date()
        let historicalStart = now.addingTimeInterval(-3600)
        var frequentTaskIDs: [UUID] = []

        for index in 1 ... WatchTransportLimits.maximumRecentTasks {
            let taskID = try #require(
                UUID(
                    uuidString: String(
                        format: "00000000-0000-0000-0000-%012X",
                        index
                    )
                )
            )
            frequentTaskIDs.append(taskID)
            let task = TaskNode(
                title: "Frequent \(index)",
                parentID: nil,
                deviceID: "fixture"
            )
            task.id = taskID
            context.insert(task)

            for segmentOffset in 0 ..< 2 {
                let startedAt = historicalStart.addingTimeInterval(
                    TimeInterval(segmentOffset * 120)
                )
                let session = TimeSession(
                    taskID: taskID,
                    source: .timer,
                    deviceID: "fixture",
                    startedAt: startedAt,
                    titleSnapshot: task.title
                )
                session.endedAt = startedAt.addingTimeInterval(60)
                context.insert(session)
                context.insert(
                    TimeSegment(
                        sessionID: session.id,
                        taskID: taskID,
                        source: .timer,
                        deviceID: "fixture",
                        startedAt: startedAt,
                        endedAt: startedAt.addingTimeInterval(60)
                    )
                )
            }
        }

        let runningTaskID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-FFFFFFFFFFFF")
        )
        let runningTask = TaskNode(
            title: "Running beyond the usage cap",
            parentID: nil,
            deviceID: "fixture"
        )
        runningTask.id = runningTaskID
        context.insert(runningTask)
        let runningSession = TimeSession(
            taskID: runningTaskID,
            source: .watch,
            deviceID: "fixture",
            startedAt: now.addingTimeInterval(-60),
            titleSnapshot: runningTask.title
        )
        context.insert(runningSession)
        let runningSegment = TimeSegment(
            sessionID: runningSession.id,
            taskID: runningTaskID,
            source: .watch,
            deviceID: "fixture",
            startedAt: runningSession.startedAt
        )
        context.insert(runningSegment)
        try context.save()

        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let snapshot = store.watchStateSnapshot(now: now)
        let expectedUsageOrder =
            Array(frequentTaskIDs.dropLast()) + [runningTaskID]
        let activeTaskIDs = Set(snapshot.activeTimers.map(\.taskID))

        #expect(snapshot.recentTasks.count == WatchTransportLimits.maximumRecentTasks)
        #expect(snapshot.recentTasks.contains { $0.taskID == runningTaskID })
        #expect(snapshot.activeTimers.contains { $0.id == runningSegment.id })
        #expect(snapshot.allTasksByUsage.map(\.taskID) == expectedUsageOrder)
        #expect(snapshot.recentTasks.contains { $0.taskID == frequentTaskIDs.last } == false)
        #expect(
            Array(
                snapshot.recentTasks
                    .filter { activeTaskIDs.contains($0.taskID) == false }
                    .prefix(WatchTransportLimits.legacyQuickStartTaskLimit)
                    .map(\.taskID)
            ) ==
                Array(
                    frequentTaskIDs.prefix(
                        WatchTransportLimits.legacyQuickStartTaskLimit
                    )
                )
        )
    }

    @Test @MainActor
    func closedAppWatchProjectionBootstrapsFullHistoryBeforeRanking() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let frequent = try taskRepository.createTask(
            title: "Frequent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let recent = try taskRepository.createTask(
            title: "Recent",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let oldStart = Date(timeIntervalSinceReferenceDate: 1000)
        _ = try timeRepository.addManualSegment(
            taskID: frequent.id,
            startedAt: oldStart,
            endedAt: oldStart.addingTimeInterval(60),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: frequent.id,
            startedAt: oldStart.addingTimeInterval(120),
            endedAt: oldStart.addingTimeInterval(180),
            note: nil
        )
        _ = try timeRepository.addManualSegment(
            taskID: recent.id,
            startedAt: oldStart.addingTimeInterval(240),
            endedAt: oldStart.addingTimeInterval(300),
            note: nil
        )

        let suiteName = "WatchHistoryBootstrap-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let store = makeTestStore()
        store.configureRepositoriesIfNeeded(context: context)
        let now = Date(timeIntervalSinceReferenceDate: 50000)

        let cacheError = try store.refreshCommittedMutationSurfaces(
            events: [
                .ledgerChanged(
                    taskID: recent.id,
                    dateInterval: nil,
                    isVisible: true
                ),
            ],
            widgetCache: WidgetSnapshotCache(
                store: SharedWidgetSnapshotStore(defaults: defaults)
            ),
            now: now
        )

        #expect(cacheError == nil)
        #expect(
            Array(
                store.watchStateSnapshot(now: now)
                    .allTasksByUsage
                    .map(\.taskID)
                    .prefix(2)
            ) ==
                [frequent.id, recent.id]
        )
    }

    @Test @MainActor
    func loadedWatchProjectionRefreshesHistoricalUsageChanges() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let initialLeader = try taskRepository.createTask(
            title: "Initial leader",
            parentID: nil
        )
        let challenger = try taskRepository.createTask(
            title: "Challenger",
            parentID: nil
        )
        let initialStart = Date(timeIntervalSinceReferenceDate: 1000)
        _ = try timeRepository.addManualSegment(
            taskID: initialLeader.id,
            startedAt: initialStart,
            endedAt: initialStart.addingTimeInterval(60),
            note: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.watchStateSnapshot().allTasksByUsage.first?.taskID == initialLeader.id)

        let challengerStart = initialStart.addingTimeInterval(1000)
        for offset in [0.0, 120.0] {
            _ = try timeRepository.addManualSegment(
                taskID: challenger.id,
                startedAt: challengerStart.addingTimeInterval(offset),
                endedAt: challengerStart.addingTimeInterval(offset + 60),
                note: nil
            )
        }
        let refreshError = try store.refreshCommittedMutationSurfaces(
            events: [
                .ledgerChanged(
                    taskID: challenger.id,
                    dateInterval: StoreInvalidationRange(
                        start: challengerStart,
                        end: challengerStart.addingTimeInterval(180)
                    ),
                    isVisible: false
                ),
            ]
        )

        #expect(refreshError == nil)
        #expect(store.watchStateSnapshot().allTasksByUsage.first?.taskID == challenger.id)
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
    func watchDashboardUsesThreeGlanceableVerticalPages() throws {
        let source = try [
            "timetrackerWatchApp/WatchDashboardView.swift",
            "timetrackerWatchApp/WatchActiveTimersPage.swift",
            "timetrackerWatchApp/WatchCommandFailuresView.swift",
            "timetrackerWatchApp/WatchCommandPresentationIndex.swift",
            "timetrackerWatchApp/WatchTaskListView.swift",
            "timetrackerWatchApp/WatchTaskRows.swift",
            "timetrackerWatchApp/WatchStatusViews.swift",
            "timetrackerWatchApp/WatchTimerRows.swift",
        ].map(sourceText).joined(separator: "\n")

        #expect(source.contains("NavigationStack"))
        #expect(source.contains("TabView(selection: $selectedPage)"))
        #expect(source.contains(".tabViewStyle(.verticalPage)"))
        #expect(source.contains(".tag(WatchDashboardPage.activeTimers)"))
        #expect(source.contains(".tag(WatchDashboardPage.quickStart)"))
        #expect(source.contains(".tag(WatchDashboardPage.allTasks)"))
        #expect(source.contains("hasSelectedInitialPage"))
        #expect(source.contains("selectInitialPageIfNeeded()"))
        #expect(source.contains("preferredInitialPage"))
        #expect(source.contains("snapshot.activeTimers.isEmpty == false"))
        #expect(source.contains("status != nil"))
        #expect(source.contains("failureItems.isEmpty == false"))
        #expect(source.contains("\"watch.page.active\""))
        #expect(source.contains("\"watch.page.quickStart\""))
        #expect(source.contains("\"watch.page.allTasks\""))
        #expect(source.contains("List {"))
        #expect(source.contains("WatchActiveTimerRow"))
        #expect(source.contains("WatchTaskShortcutRow"))
        #expect(
            source.contains(
                "WatchTransportLimits.legacyQuickStartTaskLimit"
            )
        )
        #expect(source.contains(".prefix(Self.quickStartTaskLimit)"))
        #expect(source.contains("tasks: snapshot.allTasksByUsage"))
        #expect(source.contains("!activeTaskIDs.contains($0.taskID)"))
        #expect(source.contains("isRunning: activeTaskIDs.contains(task.taskID)"))
        #expect(source.contains("onShowActiveTimers"))
        #expect(source.contains("attentionButton"))
        #expect(source.contains(".safeAreaInset(edge: .top"))
        #expect(source.contains("\"watch.attention.open\""))
        #expect(source.contains(".frame(minHeight: 44)"))
        #expect(source.contains("NavigationLink"))
        #expect(source.contains("WatchTaskListView"))
        #expect(source.contains("WatchCommandPresentationIndex"))
        #expect(source.contains("failurePreviewLimit = 1"))
        #expect(source.contains("WatchCommandFailuresView"))
        #expect(source.contains("pendingStartTaskIDs: Set<UUID>"))
        #expect(source.contains("failedStartCommandIDs: [UUID: UUID]"))
        #expect(source.contains("minHeight: 44"))
        #expect(source.contains("dynamicTypeSize >= .xxLarge"))
        #expect(source.contains(".padding(.vertical, 6)"))
        #expect(source.contains("fixedSize(horizontal: false, vertical: true)"))
        #expect(source.contains("commandState.accessibilityLabel"))
        #expect(source.contains("minimumScaleFactor(0.8)"))
        #expect(source.contains("isReachable && !hasConnectivityError ? .sending : .queued"))
        #expect(!source.contains("return .offline"))
        #expect(source.contains(".privacySensitive()"))
        #expect(source.contains("\\.isLuminanceReduced"))
        #expect(!source.contains("TimelineView"))
        #expect(!source.contains(".horizontalPage"))
        #expect(!source.contains("handGestureShortcut"))
    }

    @Test
    func watchStoreReleasesTimedOutRowsAndOffersRetryAndDiscard() throws {
        let storeFiles = [
            "timetrackerWatchApp/WatchAppStore.swift",
            "timetrackerWatchApp/WatchAppStore+Commands.swift",
            "timetrackerWatchApp/WatchAppStore+Connectivity.swift",
            "timetrackerWatchApp/WatchAppStore+SessionDelegate.swift",
        ]
        let source = try storeFiles.map(sourceText).joined(separator: "\n")
        let dashboard = try [
            "timetrackerWatchApp/WatchDashboardView.swift",
            "timetrackerWatchApp/WatchStatusViews.swift",
        ].map(sourceText).joined(separator: "\n")

        #expect(source.contains("commandQueue.enqueue(command)"))
        #expect(source.contains("commandQueue.timeOut(commandID:"))
        #expect(source.contains("func retryCommand(commandID:"))
        #expect(source.contains("func discardCommand(commandID:"))
        #expect(source.contains("decodeCommandResult"))
        #expect(source.contains("session.transferUserInfo(payload)"))
        #expect(source.contains("if includeDurableDelivery"))
        #expect(source.contains("resumePendingCommands(includeDurableDelivery: false)"))
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
        #expect(source.contains("plan.refreshPreferences"))
        #expect(facade.contains("rankedTrackableTasks()"))
        #expect(facade.contains("preferences.quickStartTaskIDs"))
        #expect(facade.contains("WatchTransportLimits.maximumRecentTasks"))
        #expect(facade.contains("quickStartRankByTaskID"))
        #expect(facade.contains("maximumSnapshotTextBytes"))
        #expect(facade.contains("boundedUTF8Prefix"))
        #expect(facade.contains("WatchConnectivityBridge.shared.updateApplicationContext"))
    }

    @Test
    func appActivatesWatchBridgeAndWeakSceneRouterRoutesIncomingCommands() throws {
        let app = try sourceText("timetracker/App/timetrackerApp.swift")
        let contentView = try sourceText("timetracker/App/ContentView.swift")
        let router = try sourceText("timetracker/App/WatchCommandRouter.swift")
        let commands = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+WatchCommands.swift")
        let processor = try sourceText("timetracker/Services/SystemIntegration/WatchCommandProcessor.swift")

        #expect(app.contains("WatchConnectivityBridge.shared.activateIfSupported"))
        #expect(contentView.contains("WatchCommandRouter.shared.register"))
        #expect(contentView.contains("WatchCommandRouter.shared.unregister"))
        #expect(!contentView.contains("WatchConnectivityBridge.shared.commandHandler"))
        #expect(router.contains("weak var value: TimeTrackerStore?"))
        #expect(router.contains("[weak self] command"))
        #expect(router.contains("WatchConnectivityBridge.shared.commandHandler = nil"))
        #expect(commands.contains("handleWatchCommand"))
        #expect(commands.contains("writeAuthorization: writeAuthorization"))
        #expect(commands.contains("processWithMutationOutcome"))
        #expect(commands.contains("timerStartMutationEvents") == false)
        #expect(processor.contains("allowParallelTimers: Bool") == false)
        #expect(processor.contains("events: outcome.events"))
    }

    @Test @MainActor
    func watchStartCommandUsesWatchSourceAndIsDurablyDeduped() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Watch task", parentID: nil, colorHex: nil, iconName: nil)
        let receiptStore = InMemoryWatchCommandReceiptStore()
        let processor = makeTestWatchCommandProcessor(receiptStore: receiptStore)
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1000)
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
            context: context,
            now: issuedAt
        )
        try makeTestSystemActionCommandHandler().stopTimer(taskID: task.id, context: context)
        let duplicateResult = try processor.process(
            command,
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
    func watchRapidRestartCoalescesThroughCommandProcessor() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(
            context: context,
            deviceID: "test"
        ).createTask(
            title: "Watch rapid restart",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let processor = makeTestWatchCommandProcessor(
            receiptStore: InMemoryWatchCommandReceiptStore()
        )
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1100)
        let start = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: task.id,
            segmentID: nil,
            issuedAt: issuedAt,
            deviceID: "watch-test"
        )
        guard case let .started(predecessorID) = try processor.process(
            start,
            context: context,
            now: issuedAt
        ) else {
            Issue.record("The initial Watch timer did not start")
            return
        }
        let fixtureContext = ModelContext(context.container)
        let predecessor = try #require(
            try fixtureContext.fetch(FetchDescriptor<TimeSegment>())
                .first { $0.id == predecessorID }
        )
        let session = try #require(
            try fixtureContext.fetch(FetchDescriptor<TimeSession>())
                .first { $0.id == predecessor.sessionID }
        )
        let sessionID = session.id
        let backdatedStart = issuedAt.addingTimeInterval(-120)
        predecessor.startedAt = backdatedStart
        session.startedAt = backdatedStart
        try fixtureContext.save()

        let stop = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: predecessorID,
            issuedAt: issuedAt.addingTimeInterval(1),
            deviceID: "watch-test"
        )
        let stopped = try processor.process(
            stop,
            context: context,
            now: stop.issuedAt
        )
        let restart = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: task.id,
            segmentID: nil,
            issuedAt: issuedAt.addingTimeInterval(2),
            deviceID: "watch-test"
        )
        let restarted = try processor.process(
            restart,
            context: context,
            now: restart.issuedAt
        )

        let replacementID = TimerRapidRestartPolicy()
            .replacementSegmentID(predecessorSegmentID: predecessorID)
        #expect(stopped == .stopped(predecessorID))
        #expect(restarted == .started(replacementID))
        let verificationContext = ModelContext(context.container)
        let rawSegments = try verificationContext.fetch(
            FetchDescriptor<TimeSegment>()
        )
        let visibleSegments = try SwiftDataTimeTrackingRepository(
            context: verificationContext,
            deviceID: "test"
        ).allSegments()
        #expect(rawSegments.count == 2)
        #expect(rawSegments.first { $0.id == predecessorID }?.deletedAt != nil)
        #expect(visibleSegments.map(\.id) == [replacementID])
        #expect(visibleSegments.first?.sessionID == sessionID)
        #expect(visibleSegments.first?.startedAt == backdatedStart)
        #expect(visibleSegments.first?.source == .watch)
        #expect(visibleSegments.first?.endedAt == nil)
    }

    @Test @MainActor
    func watchStartReReadsTheExclusiveTimerSettingInsideTheStoreTransaction() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let runningTask = try taskRepository.createTask(
            title: "Already running",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let requestedTask = try taskRepository.createTask(
            title: "Watch request",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let runningSegment = try timeRepository.startTask(
            taskID: runningTask.id,
            source: .timer
        )
        try PreferenceCommandHandler().set(
            key: .allowParallelTimers,
            valueJSON: PreferenceJSON.encode(false),
            context: context
        )
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: requestedTask.id,
            segmentID: nil,
            issuedAt: Date(),
            deviceID: "watch-test"
        )

        let result = try makeTestWatchCommandProcessor(
            receiptStore: InMemoryWatchCommandReceiptStore()
        ).process(command, context: context)

        guard case let .started(startedID) = result else {
            Issue.record("The requested watch timer should start")
            return
        }
        #expect(try timeRepository.activeSegments().map(\.id) == [startedID])
        #expect(try timeRepository.allSegments().first { $0.id == runningSegment.id }?.endedAt != nil)
    }

    @Test @MainActor
    func watchCanStartAnotherTaskWhileParallelTimersAreEnabled() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let runningTask = try taskRepository.createTask(
            title: "Already running",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let requestedTask = try taskRepository.createTask(
            title: "Watch request",
            parentID: nil,
            colorHex: nil,
            iconName: nil
        )
        let runningSegment = try timeRepository.startTask(
            taskID: runningTask.id,
            source: .timer
        )
        try PreferenceCommandHandler().set(
            key: .allowParallelTimers,
            valueJSON: PreferenceJSON.encode(true),
            context: context
        )
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: requestedTask.id,
            segmentID: nil,
            issuedAt: Date(),
            deviceID: "watch-test"
        )

        let result = try makeTestWatchCommandProcessor(
            receiptStore: InMemoryWatchCommandReceiptStore()
        ).process(command, context: context)

        guard case let .started(startedID) = result else {
            Issue.record("The requested watch timer should start")
            return
        }
        #expect(try Set(timeRepository.activeSegments().map(\.id)) == [runningSegment.id, startedID])
    }

    @Test @MainActor
    func watchFacadeRefreshesAnExternallyStartedTimerThatTheCommandReuses() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Started elsewhere",
            parentID: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.activeSegment(for: task.id) == nil)

        let stateDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "WatchReuse-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: stateDirectory) }

        try withWatchCloudSyncMode {
            let service = SyncConflictService(
                stateURL: stateDirectory.appendingPathComponent("state.json")
            )
            #expect(try service.bootstrap(context: context) == nil)
            let generationBeforeReuse = try service.loadState().localGeneration
            let siblingContext = ModelContext(context.container)
            let siblingRepository = SwiftDataTimeTrackingRepository(
                context: siblingContext,
                deviceID: "sibling"
            )
            let existingSegment = try siblingRepository.startTask(
                taskID: task.id,
                source: .timer
            )
            let command = WatchTimerCommand(
                id: UUID(),
                type: .startTask,
                taskID: task.id,
                segmentID: nil,
                issuedAt: Date(),
                deviceID: "watch-test"
            )

            let result = store.handleWatchCommand(
                command,
                recordingWith: service
            )

            #expect(result.status == .success)
            #expect(result.relatedID == existingSegment.id)
            #expect(
                store.watchStateSnapshot().activeTimers.contains {
                    $0.id == existingSegment.id
                }
            )
            #expect(try service.loadState().localGeneration == generationBeforeReuse)
        }
    }

    @Test @MainActor
    func missingWatchStopRefreshesAnExternallyStoppedTimer() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let timeRepository = SwiftDataTimeTrackingRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Stopped elsewhere",
            parentID: nil
        )
        let segment = try timeRepository.startTask(
            taskID: task.id,
            source: .timer
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.watchStateSnapshot().activeTimers.contains { $0.id == segment.id })

        let siblingContext = ModelContext(context.container)
        try SwiftDataTimeTrackingRepository(
            context: siblingContext,
            deviceID: "sibling"
        ).stopSegment(segmentID: segment.id)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: segment.id,
            issuedAt: Date(),
            deviceID: "watch-test"
        )

        let result = store.handleWatchCommand(
            command,
            recordingWith: SyncConflictService(
                stateURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "WatchMissingSegment-\(UUID().uuidString).json"
                    )
            )
        )

        #expect(result.status == .missingSegment)
        #expect(
            store.watchStateSnapshot().activeTimers.contains {
                $0.id == segment.id
            } == false
        )
    }

    @Test @MainActor
    func missingWatchStartRefreshesAnExternallyArchivedTask() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(
            title: "Archived elsewhere",
            parentID: nil
        )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        #expect(store.watchStateSnapshot().recentTasks.contains { $0.taskID == task.id })

        let siblingContext = ModelContext(context.container)
        try SwiftDataTaskRepository(
            context: siblingContext,
            deviceID: "sibling"
        ).archiveTask(taskID: task.id)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: task.id,
            segmentID: nil,
            issuedAt: Date(),
            deviceID: "watch-test"
        )

        let result = store.handleWatchCommand(
            command,
            recordingWith: SyncConflictService(
                stateURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent(
                        "WatchMissingTask-\(UUID().uuidString).json"
                    )
            )
        )

        #expect(result.status == .missingTask)
        #expect(
            store.watchStateSnapshot().recentTasks.contains {
                $0.taskID == task.id
            } == false
        )
    }

    @Test @MainActor
    func missingWatchStartCommandCanBeRetriedAfterTaskArrives() throws {
        let context = try makeTestContext()
        let receiptStore = InMemoryWatchCommandReceiptStore()
        let processor = makeTestWatchCommandProcessor(receiptStore: receiptStore)
        let taskID = UUID()
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1000)
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
            context: context,
            now: issuedAt
        )
        let task = TaskNode(title: "Late task", parentID: nil, deviceID: "test")
        task.id = taskID
        context.insert(task)
        try context.save()
        let retryResult = try processor.process(
            command,
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
        let processor = makeTestWatchCommandProcessor(receiptStore: receiptStore)
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1100)
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
            context: context,
            now: issuedAt
        )
        let duplicateResult = try processor.process(
            command,
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
        let processor = makeTestWatchCommandProcessor(receiptStore: receiptStore)
        let commandID = UUID()
        let issuedAt = Date(timeIntervalSinceReferenceDate: 1200)
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
        let processor = makeTestWatchCommandProcessor(receiptStore: receiptStore)
        let command = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: segment.id,
            issuedAt: Date(),
            deviceID: "watch-test"
        )

        let result = try processor.process(command, context: context)

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
        let store = makeTestStore()
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
            #expect(try service.loadState().localSnapshot?.segments.contains { $0.id == segment.id } == true)
        }
    }
}

@MainActor
private func withWatchCloudSyncMode(_ body: () throws -> Void) throws {
    let defaults = AppDefaults.shared
    let previousMode = defaults.object(forKey: AppCloudSync.modeKey)
    let previousUploadReset = defaults.object(forKey: AppCloudSync.pendingCloudUploadResetKey)
    let previousDownloadReset = defaults.object(forKey: AppCloudSync.pendingCloudDownloadResetKey)
    let previousQueuedReconciliation = defaults.object(forKey: AppCloudSync.queuedCloudReconciliationKey)
    let previousActiveReconciliation = defaults.object(forKey: AppCloudSync.activeCloudReconciliationKey)
    let previousCloudRecoveryStoreReset = defaults.object(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
    let previousActiveCloudDownloadRecovery = defaults.object(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
    defaults.set(AppCloudSync.modeICloud, forKey: AppCloudSync.modeKey)
    defaults.removeObject(forKey: AppCloudSync.pendingCloudUploadResetKey)
    defaults.removeObject(forKey: AppCloudSync.pendingCloudDownloadResetKey)
    defaults.removeObject(forKey: AppCloudSync.queuedCloudReconciliationKey)
    defaults.removeObject(forKey: AppCloudSync.activeCloudReconciliationKey)
    defaults.removeObject(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
    defaults.removeObject(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
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
        if let previousQueuedReconciliation {
            defaults.set(previousQueuedReconciliation, forKey: AppCloudSync.queuedCloudReconciliationKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.queuedCloudReconciliationKey)
        }
        if let previousActiveReconciliation {
            defaults.set(previousActiveReconciliation, forKey: AppCloudSync.activeCloudReconciliationKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.activeCloudReconciliationKey)
        }
        if let previousCloudRecoveryStoreReset {
            defaults.set(previousCloudRecoveryStoreReset, forKey: AppCloudSync.cloudRecoveryStoreResetKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.cloudRecoveryStoreResetKey)
        }
        if let previousActiveCloudDownloadRecovery {
            defaults.set(previousActiveCloudDownloadRecovery, forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
        } else {
            defaults.removeObject(forKey: AppCloudSync.activeCloudDownloadRecoveryKey)
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

private struct WatchCommandQueueFixture: Encodable {
    let pendingCommands: [WatchTimerCommand]
    let failedCommands: [WatchFailedCommand]
}
