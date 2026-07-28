import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CommittedMutationSystemSurfaceMaterializerTests {
    @Test @MainActor
    func materializesCommittedFactsForEverySystemSurface()
        async throws
    {
        try await withSystemSurfaceMaterializerFixture(
            name: #function
        ) { fixture in
            let now = Date(timeIntervalSinceReferenceDate: 800_000_000)
            let context = ModelContext(fixture.container)
            context.autosaveEnabled = false

            let parent = TaskNode(
                title: "Project",
                parentID: nil,
                deviceID: "surface-materializer-test",
                colorHex: "1677FF",
                iconName: "folder"
            )
            parent.createdAt = now.addingTimeInterval(-20000)
            parent.updatedAt = now.addingTimeInterval(-100)
            let child = TaskNode(
                title: "Focus",
                parentID: parent.id,
                deviceID: "surface-materializer-test",
                colorHex: "FF3B30",
                iconName: "timer"
            )
            child.createdAt = now.addingTimeInterval(-10000)
            child.updatedAt = now.addingTimeInterval(-200)

            let firstSession = TimeSession(
                taskID: child.id,
                source: .timer,
                deviceID: "surface-materializer-test",
                startedAt: now.addingTimeInterval(-3600)
            )
            let firstSegment = TimeSegment(
                sessionID: firstSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "surface-materializer-test",
                startedAt: now.addingTimeInterval(-3600),
                endedAt: now.addingTimeInterval(-1800)
            )
            let secondSession = TimeSession(
                taskID: child.id,
                source: .timer,
                deviceID: "surface-materializer-test",
                startedAt: now.addingTimeInterval(-3000)
            )
            let secondSegment = TimeSegment(
                sessionID: secondSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "surface-materializer-test",
                startedAt: now.addingTimeInterval(-3000),
                endedAt: now.addingTimeInterval(-1200)
            )
            let activeSession = TimeSession(
                taskID: child.id,
                source: .timer,
                deviceID: "surface-materializer-test",
                startedAt: now.addingTimeInterval(-600)
            )
            let activeSegment = TimeSegment(
                sessionID: activeSession.id,
                taskID: child.id,
                source: .timer,
                deviceID: "surface-materializer-test",
                startedAt: now.addingTimeInterval(-600)
            )
            let quickStart = SyncedPreference(
                key: AppPreferenceKey.quickStartTaskIDs.rawValue,
                valueJSON: PreferenceJSON.encode([
                    parent.id.uuidString,
                ]),
                deviceID: "surface-materializer-test"
            )

            context.insert(parent)
            context.insert(child)
            context.insert(firstSession)
            context.insert(firstSegment)
            context.insert(secondSession)
            context.insert(secondSegment)
            context.insert(activeSession)
            context.insert(activeSegment)
            context.insert(quickStart)
            try context.save()

            let materialization = try await materializationMatchingStore(
                fixture: fixture,
                context: context,
                now: now,
                calendar: .current
            )

            #expect(materialization.generatedAt == now)
            #expect(
                materialization.widgetSnapshot.todayGrossSeconds ==
                    4200
            )
            #expect(
                materialization.widgetSnapshot.todayWallSeconds ==
                    3000
            )
            #expect(
                materialization.widgetSnapshot.activeTimers.map(\.id) ==
                    [activeSegment.id]
            )
            #expect(
                materialization.widgetSnapshot.activeTimers.first?.title ==
                    "Focus"
            )
            #expect(
                materialization.widgetSnapshot.activeTimers.first?.path ==
                    "Project"
            )
            #expect(
                materialization.widgetSnapshot.recentTasks.map(\.taskID) ==
                    [parent.id]
            )
            #expect(
                materialization.widgetSnapshot.isStructurallyValid
            )

            #expect(
                materialization.watchSnapshot.activeTimers.map(\.id) ==
                    [activeSegment.id]
            )
            #expect(
                materialization.watchSnapshot.recentTasks
                    .first(where: { $0.taskID == parent.id })?
                    .quickStartRank == 0
            )
            #expect(
                materialization.watchSnapshot.allTasksByUsage
                    .first?.taskID == child.id
            )
            #expect(
                materialization.watchSnapshot.isValid(at: now)
            )

            guard case let .active(liveActivity) =
                materialization.liveActivity
            else {
                Issue.record("Expected an active Live Activity projection.")
                return
            }
            #expect(liveActivity.segmentID == activeSegment.id.uuidString)
            #expect(liveActivity.taskID == child.id.uuidString)
            #expect(liveActivity.taskTitle == "Focus")
            #expect(liveActivity.taskPath == "/Project/Focus")
            #expect(liveActivity.taskPathAbbreviated == "/P/F")
        }
    }

    @Test @MainActor
    func matchesStoreForUnreadableLedgerAndPartialRecurrenceGraphs()
        async throws
    {
        try await withSystemSurfaceMaterializerFixture(
            name: #function
        ) { fixture in
            let now = Date(timeIntervalSinceReferenceDate: 800_100_000)
            let context = ModelContext(fixture.container)
            context.autosaveEnabled = false
            let deviceID = "surface-materializer-relationships"

            let ordinaryTask = TaskNode(
                title: "Readable",
                parentID: nil,
                deviceID: deviceID
            )
            let recurrenceTemplate = TaskNode(
                title: "Incomplete template",
                parentID: nil,
                deviceID: deviceID
            )
            let generatedTask = TaskNode(
                title: "Incomplete occurrence",
                parentID: recurrenceTemplate.id,
                deviceID: deviceID
            )
            let partialOccurrence = TaskRecurrenceOccurrence(
                ruleID: UUID(),
                templateTaskID: recurrenceTemplate.id,
                occurrenceDayKey: "2026-07-28",
                timeZoneIdentifier: "UTC",
                deviceID: deviceID
            )
            partialOccurrence.generatedTaskID = generatedTask.id

            let readableSession = TimeSession(
                taskID: ordinaryTask.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: now.addingTimeInterval(-300)
            )
            let readableSegment = TimeSegment(
                sessionID: readableSession.id,
                taskID: ordinaryTask.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: readableSession.startedAt
            )
            let missingSessionSegment = TimeSegment(
                sessionID: UUID(),
                taskID: ordinaryTask.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: now.addingTimeInterval(-240)
            )
            let tombstonedSession = TimeSession(
                taskID: ordinaryTask.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: now.addingTimeInterval(-180)
            )
            tombstonedSession.deletedAt =
                now.addingTimeInterval(-120)
            let tombstonedSessionSegment = TimeSegment(
                sessionID: tombstonedSession.id,
                taskID: ordinaryTask.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: tombstonedSession.startedAt
            )
            let missingTaskID = UUID()
            let missingTaskSession = TimeSession(
                taskID: missingTaskID,
                source: .timer,
                deviceID: deviceID,
                startedAt: now.addingTimeInterval(-120)
            )
            let missingTaskSegment = TimeSegment(
                sessionID: missingTaskSession.id,
                taskID: missingTaskID,
                source: .timer,
                deviceID: deviceID,
                startedAt: missingTaskSession.startedAt
            )
            let tombstonedSegmentSession = TimeSession(
                taskID: ordinaryTask.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: now.addingTimeInterval(-60)
            )
            let tombstonedSegment = TimeSegment(
                sessionID: tombstonedSegmentSession.id,
                taskID: ordinaryTask.id,
                source: .timer,
                deviceID: deviceID,
                startedAt: tombstonedSegmentSession.startedAt
            )
            tombstonedSegment.deletedAt =
                now.addingTimeInterval(-30)

            [
                ordinaryTask,
                recurrenceTemplate,
                generatedTask,
            ].forEach(context.insert)
            context.insert(partialOccurrence)
            context.insert(readableSession)
            context.insert(readableSegment)
            context.insert(missingSessionSegment)
            context.insert(tombstonedSession)
            context.insert(tombstonedSessionSegment)
            context.insert(missingTaskSession)
            context.insert(missingTaskSegment)
            context.insert(tombstonedSegmentSession)
            context.insert(tombstonedSegment)
            try context.save()

            let materialization = try await materializationMatchingStore(
                fixture: fixture,
                context: context,
                now: now,
                calendar: .current
            )
            let visibleWatchTaskIDs = Set(
                materialization.watchSnapshot.recentTasks.map(\.taskID)
            )

            #expect(
                materialization.widgetSnapshot.activeTimers.map(\.id) ==
                    [readableSegment.id]
            )
            #expect(
                materialization.watchSnapshot.activeTimers.map(\.id) ==
                    [readableSegment.id]
            )
            #expect(
                materialization.watchSnapshot.todayGrossSeconds == 300
            )
            #expect(visibleWatchTaskIDs.contains(ordinaryTask.id))
            #expect(
                visibleWatchTaskIDs.contains(recurrenceTemplate.id) ==
                    false
            )
            #expect(
                visibleWatchTaskIDs.contains(generatedTask.id) ==
                    false
            )
            #expect(
                materialization.watchSnapshot.isValid(at: now)
            )
        }
    }

    @Test @MainActor
    func matchesStoreAtUnicodeWatchTextBudgetBoundary()
        async throws
    {
        try await withSystemSurfaceMaterializerFixture(
            name: #function
        ) { fixture in
            let now = Date(timeIntervalSinceReferenceDate: 800_200_000)
            let context = ModelContext(fixture.container)
            context.autosaveEnabled = false
            let deviceID = "surface-materializer-unicode"
            let parent = TaskNode(
                title: String(repeating: "🧭", count: 300),
                parentID: nil,
                deviceID: deviceID
            )
            context.insert(parent)

            var taskIDs: [UUID] = []
            for index in 1 ... 270 {
                let taskID = try #require(UUID(
                    uuidString: String(
                        format:
                        "00000000-0000-0000-0000-%012X",
                        index
                    )
                ))
                let task = TaskNode(
                    title: String(repeating: "🧪", count: 200),
                    parentID: parent.id,
                    deviceID: deviceID,
                    colorHex: String(repeating: "A", count: 200),
                    iconName: String(repeating: "🌀", count: 40)
                )
                task.id = taskID
                task.createdAt = now.addingTimeInterval(
                    TimeInterval(-index)
                )
                task.updatedAt = now
                taskIDs.append(taskID)
                context.insert(task)
            }
            let quickStartTaskIDs = Array(
                taskIDs.suffix(
                    WatchTransportLimits.maximumQuickStartTasks
                ).reversed()
            )
            context.insert(SyncedPreference(
                key: AppPreferenceKey.quickStartTaskIDs.rawValue,
                valueJSON: PreferenceJSON.encode(
                    quickStartTaskIDs.map(\.uuidString)
                ),
                deviceID: deviceID
            ))
            try context.save()

            let materialization = try await materializationMatchingStore(
                fixture: fixture,
                context: context,
                now: now,
                calendar: .current
            )
            let snapshot = materialization.watchSnapshot
            let projectedTextByteCount = snapshot.activeTimers.reduce(
                into: 0
            ) { total, timer in
                total += WatchTransportLimits.textByteCount(
                    title: timer.title,
                    path: timer.path,
                    colorHex: timer.colorHex,
                    iconName: timer.iconName
                )
            } + snapshot.recentTasks.reduce(into: 0) {
                total,
                task in
                total += WatchTransportLimits.textByteCount(
                    title: task.title,
                    path: task.path,
                    colorHex: task.colorHex,
                    iconName: task.iconName
                )
            }
            let selectedQuickStartTaskIDs = snapshot.recentTasks
                .filter { $0.quickStartRank != nil }
                .sorted {
                    ($0.quickStartRank ?? .max) <
                        ($1.quickStartRank ?? .max)
                }
                .map(\.taskID)
            let firstQuickStart = try #require(
                snapshot.recentTasks.first {
                    $0.taskID == quickStartTaskIDs[0]
                }
            )

            #expect(snapshot.isValid(at: now))
            #expect(
                projectedTextByteCount <=
                    WatchTransportLimits.maximumSnapshotTextBytes
            )
            #expect(
                snapshot.recentTasks.count <
                    WatchTransportLimits.maximumRecentTasks
            )
            #expect(selectedQuickStartTaskIDs == quickStartTaskIDs)
            #expect(
                Array(
                    snapshot.recentTasks
                        .prefix(quickStartTaskIDs.count)
                        .map(\.taskID)
                ) == quickStartTaskIDs
            )
            #expect(
                firstQuickStart.title.utf8.count ==
                    WatchTransportLimits.maximumProjectedTitleBytes
            )
            #expect(
                firstQuickStart.path.utf8.count ==
                    WatchTransportLimits.maximumProjectedPathBytes
            )
            #expect(
                firstQuickStart.colorHex?.utf8.count ==
                    WatchTransportLimits
                    .maximumProjectedStyleValueBytes
            )
            #expect(
                firstQuickStart.iconName?.utf8.count ==
                    WatchTransportLimits
                    .maximumProjectedStyleValueBytes
            )
        }
    }

    @Test @MainActor
    func completedDatabaseReadAndMaterializationDoNotBlockMainActorHeartbeat()
        async throws
    {
        try await withSystemSurfaceMaterializerFixture(
            name: #function
        ) { fixture in
            let context = ModelContext(fixture.container)
            context.autosaveEnabled = false
            context.insert(TaskNode(
                title: "Persistent fact",
                parentID: nil,
                deviceID: "surface-materializer-heartbeat"
            ))
            try context.save()

            let gate = SystemSurfaceMaterializationBlockingGate()
            let materializer =
                CommittedMutationSystemSurfaceMaterializer(
                    modelContainer: fixture.container
                )
            let coordinator = Task.detached {
                await gate.waitUntilBlocked()
                let safetyRelease = Task.detached {
                    try? await Task.sleep(for: .seconds(2))
                    gate.releaseOnce(from: .safety)
                }
                await Task { @MainActor in
                    gate.releaseOnce(from: .heartbeat)
                }.value
                safetyRelease.cancel()
                _ = await safetyRelease.result
            }
            let run = Task.detached {
                try await materializer.materialize {
                    checkpoint in
                    if checkpoint == .afterMaterialization {
                        gate.block()
                    }
                }
            }

            _ = try await run.value
            await coordinator.value

            #expect(gate.firstRelease == .heartbeat)
        }
    }

    @MainActor
    private func materializationMatchingStore(
        fixture: SystemSurfaceMaterializerFixture,
        context: ModelContext,
        now: Date,
        calendar: Calendar
    ) async throws
        -> CommittedMutationSystemProjectionMaterialization
    {
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        let storeSnapshot = store.watchStateSnapshot(now: now)
        let materializer =
            CommittedMutationSystemSurfaceMaterializer(
                modelContainer: fixture.container
            )
        let materialization = try await materializer.materialize(
            now: now,
            calendar: calendar
        )
        #expect(materialization.watchSnapshot == storeSnapshot)
        return materialization
    }
}

@MainActor
private final class SystemSurfaceMaterializerFixture {
    let container: ModelContainer
    let directory: URL

    init(name: String) throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "SystemSurfaceMaterializerTests-\(name)-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        let schema = TimeTrackerModelRegistry.currentSchema
        let configuration = ModelConfiguration(
            "SystemSurfaceMaterializer",
            schema: schema,
            url: directory.appendingPathComponent("timetracker.store"),
            cloudKitDatabase: .none
        )
        container = try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }
}

@MainActor
private func withSystemSurfaceMaterializerFixture(
    name: String,
    operation: @MainActor (
        SystemSurfaceMaterializerFixture
    ) async throws -> Void
) async throws {
    var fixture: SystemSurfaceMaterializerFixture?
    do {
        fixture = try SystemSurfaceMaterializerFixture(name: name)
        let directory = try #require(fixture?.directory)
        try await operation(#require(fixture))
        fixture = nil
        try? FileManager.default.removeItem(at: directory)
    } catch {
        let directory = fixture?.directory
        fixture = nil
        if let directory {
            try? FileManager.default.removeItem(at: directory)
        }
        throw error
    }
}

private final nonisolated class SystemSurfaceMaterializationBlockingGate:
    @unchecked Sendable
{
    enum ReleaseSource: Equatable {
        case heartbeat
        case safety
    }

    private let lock = NSLock()
    private let resume = DispatchSemaphore(value: 0)
    private var isBlocked = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    private var releaseSource: ReleaseSource?

    var firstRelease: ReleaseSource? {
        lock.withLock { releaseSource }
    }

    func block() {
        let waiters = lock.withLock {
            isBlocked = true
            defer { self.waiters.removeAll() }
            return self.waiters
        }
        waiters.forEach { $0.resume() }
        resume.wait()
    }

    func waitUntilBlocked() async {
        await withCheckedContinuation { continuation in
            let resumeImmediately = lock.withLock {
                guard isBlocked == false else { return true }
                waiters.append(continuation)
                return false
            }
            if resumeImmediately {
                continuation.resume()
            }
        }
    }

    func releaseOnce(from source: ReleaseSource) {
        let shouldSignal = lock.withLock {
            guard releaseSource == nil else { return false }
            releaseSource = source
            return true
        }
        if shouldSignal {
            resume.signal()
        }
    }
}
