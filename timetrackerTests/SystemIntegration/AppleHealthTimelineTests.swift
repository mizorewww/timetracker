import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct AppleHealthTimelineTests {
    @Test
    func projectionClipsWorkoutsCanonicalizesDuplicateIDsAndKeepsNamespacedIdentity() throws {
        let service = AppleHealthTimelineProjectionService()
        let bounds = DateInterval(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 500)
        )
        let sharedID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000010")
        )
        let laterID = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000020")
        )
        let duplicateInvalid = workout(
            id: sharedID,
            kind: .walking,
            start: 300,
            end: 200,
            source: "invalid"
        )
        let duplicateValid = workout(
            id: sharedID,
            kind: .running,
            start: 50,
            end: 200,
            source: "valid"
        )
        let later = workout(
            id: laterID,
            kind: .cycling,
            start: 450,
            end: 700
        )
        let touchesEnd = workout(
            id: UUID(),
            kind: .walking,
            start: 500,
            end: 600
        )

        let items = service.project(
            batch: AppleHealthSampleBatch(
                workouts: [later, duplicateInvalid, touchesEnd, duplicateValid],
                sleep: []
            ),
            visibleInterval: bounds
        )

        #expect(items.count == 2)
        #expect(items.map(\.id) == [
            .appleHealthWorkout(sharedID),
            .appleHealthWorkout(laterID),
        ])
        #expect(items.map(\.subject) == [
            .appleHealthWorkout(.running),
            .appleHealthWorkout(.cycling),
        ])
        #expect(items.map(\.interval) == [
            DateInterval(start: bounds.start, end: Date(timeIntervalSince1970: 200)),
            DateInterval(start: Date(timeIntervalSince1970: 450), end: bounds.end),
        ])
    }

    @Test
    func projectionMergesActualSleepAcrossSourcesAndIgnoresInBedAndAwake() throws {
        let service = AppleHealthTimelineProjectionService()
        let bounds = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1_000)
        )
        let firstID = try fixedID(1)
        let secondID = try fixedID(2)
        let thirdID = try fixedID(3)
        let separateID = try fixedID(4)
        let samples = [
            sleep(id: UUID(), stage: .inBed, start: 0, end: 900, source: "phone"),
            sleep(id: UUID(), stage: .awake, start: 300, end: 400, source: "watch"),
            sleep(id: firstID, stage: .asleepCore, start: 100, end: 300, source: "watch"),
            sleep(id: secondID, stage: .asleepDeep, start: 250, end: 500, source: "watch"),
            sleep(id: thirdID, stage: .asleepREM, start: 500, end: 600, source: "other"),
            sleep(id: separateID, stage: .asleepUnspecified, start: 700, end: 800, source: "phone"),
        ]

        let forward = service.project(
            batch: AppleHealthSampleBatch(workouts: [], sleep: samples),
            visibleInterval: bounds
        )
        let reversed = service.project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: Array(samples.reversed())
            ),
            visibleInterval: bounds
        )

        #expect(forward == reversed)
        #expect(forward.count == 2)
        #expect(forward.map(\.subject) == [.appleHealthSleep, .appleHealthSleep])
        #expect(forward.map(\.interval) == [
            DateInterval(
                start: Date(timeIntervalSince1970: 100),
                end: Date(timeIntervalSince1970: 600)
            ),
            DateInterval(
                start: Date(timeIntervalSince1970: 700),
                end: Date(timeIntervalSince1970: 800)
            ),
        ])
        #expect(forward.first?.id == .appleHealthSleep([firstID, secondID, thirdID]))
        #expect(forward.last?.id == .appleHealthSleep([separateID]))
    }

    @Test
    func projectionClipsCrossMidnightSleepAndDropsNonPositiveOrTouchingIntervals() {
        let service = AppleHealthTimelineProjectionService()
        let bounds = DateInterval(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200)
        )
        let samples = [
            sleep(id: UUID(), stage: .asleepCore, start: 50, end: 150),
            sleep(id: UUID(), stage: .asleepDeep, start: 180, end: 250),
            sleep(id: UUID(), stage: .asleepREM, start: 200, end: 250),
            sleep(id: UUID(), stage: .asleepREM, start: 170, end: 170),
        ]

        let items = service.project(
            batch: AppleHealthSampleBatch(workouts: [], sleep: samples),
            visibleInterval: bounds
        )

        #expect(items.map(\.interval) == [
            DateInterval(
                start: Date(timeIntervalSince1970: 100),
                end: Date(timeIntervalSince1970: 150)
            ),
            DateInterval(
                start: Date(timeIntervalSince1970: 180),
                end: Date(timeIntervalSince1970: 200)
            ),
        ])
    }

    @Test @MainActor
    func mixedTimelineUsesOneLayoutAndKeepsLedgerAndHealthIDsDistinct() throws {
        let sharedID = try fixedID(9)
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200)
        )
        let tracked = TimelinePresentationSeed(
            id: .trackedSegment(sharedID),
            subject: .task(sharedID),
            title: "Tracked",
            path: "Task",
            iconName: "checkmark",
            colorHex: "0A84FF",
            interval: interval
        )
        let health = TimelinePresentationSeed(
            id: .appleHealthWorkout(sharedID),
            subject: .appleHealthWorkout(.running),
            title: "Running",
            path: "Exercise",
            iconName: "figure.run",
            colorHex: "FF3B30",
            interval: interval
        )

        let snapshot = AnalyticsTimelineSnapshotService().snapshot(
            seeds: [health, tracked],
            visibleInterval: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 300)
            )
        )

        #expect(snapshot.entries.map(\.id) == [
            .trackedSegment(sharedID),
            .appleHealthWorkout(sharedID),
        ])
        #expect(snapshot.entries.map(\.lane) == [0, 1])
        #expect(snapshot.laneCount == 2)
    }

    @Test
    func layoutEngineUsesNamespacedIDTieBreakForStableLanes() throws {
        let sharedID = try fixedID(10)
        let interval = DateInterval(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200)
        )
        let tracked = TimelineLayoutItem(
            id: .trackedSegment(sharedID),
            startedAt: interval.start,
            endedAt: interval.end
        )
        let health = TimelineLayoutItem(
            id: .appleHealthWorkout(sharedID),
            startedAt: interval.start,
            endedAt: interval.end
        )
        let visibleInterval = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 300)
        )

        let forward = TimelineLayoutEngine.layout(
            items: [tracked, health],
            dayInterval: visibleInterval
        )
        let reversed = TimelineLayoutEngine.layout(
            items: [health, tracked],
            dayInterval: visibleInterval
        )

        #expect(forward.entries.map(\.id) == reversed.entries.map(\.id))
        #expect(forward.entries.map(\.lane) == reversed.entries.map(\.lane))
        #expect(forward.entries.map(\.id) == [
            .trackedSegment(sharedID),
            .appleHealthWorkout(sharedID),
        ])
        #expect(forward.entries.map(\.lane) == [0, 1])
    }

    @Test @MainActor
    func disabledStoreNeverRequestsAccessAndUserActionLoadsOnlyThroughMemory() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let workoutID = try fixedID(20)
        let reader = StubAppleHealthReader(
            batch: AppleHealthSampleBatch(
                workouts: [
                    AppleHealthWorkoutSample(
                        id: workoutID,
                        kind: .running,
                        startedAt: now.addingTimeInterval(-1_800),
                        endedAt: now.addingTimeInterval(-1_200),
                        sourceBundleIdentifier: "test"
                    ),
                ],
                sleep: []
            )
        )
        let preferences = StubAppleHealthTimelinePreferences(isTimelineEnabled: false)
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences
        )

        await store.refreshAppleHealthTimelineIfEnabled(now: now, calendar: calendar)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.isEmpty)

        await store.showAppleHealthInTimeline(now: now, calendar: calendar)

        #expect(reader.authorizationRequestCount == 1)
        #expect(reader.sampleRequestIntervals.count == 1)
        #expect(reader.sampleRequestIntervals.first?.start == calendar.startOfDay(for: now))
        #expect(reader.sampleRequestIntervals.first?.end == now)
        #expect(preferences.isTimelineEnabled)
        #expect(store.appleHealthTimelineItems.count == 1)
        #expect(
            store.appleHealthTimelineState == .content(
                interval: try #require(reader.sampleRequestIntervals.first),
                refreshedAt: now,
                itemCount: 1
            )
        )

        let timeline = store.timelineSnapshot(
            segments: [],
            date: now,
            now: now,
            calendar: calendar
        )
        #expect(timeline.entries.map(\.subject) == [.appleHealthWorkout(.running)])
        #expect(store.todayGrossSeconds(now: now, calendar: calendar) == 0)
        #expect(store.todayWallSeconds(now: now, calendar: calendar) == 0)

        store.hideAppleHealthFromTimeline()
        #expect(preferences.isTimelineEnabled == false)
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(store.appleHealthTimelineState == .disabled)
    }

    @Test @MainActor
    func enabledRefreshQueriesWithoutRequestingAuthorizationAgain() async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let reader = StubAppleHealthReader(
            batch: AppleHealthSampleBatch(
                workouts: [
                    AppleHealthWorkoutSample(
                        id: try fixedID(21),
                        kind: .walking,
                        startedAt: now.addingTimeInterval(-600),
                        endedAt: now.addingTimeInterval(-300),
                        sourceBundleIdentifier: "test"
                    ),
                ],
                sleep: []
            )
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: true
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences
        )

        await store.refreshAppleHealthTimelineIfEnabled(
            now: now,
            calendar: calendar
        )

        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.count == 1)
        #expect(store.appleHealthTimelineItems.count == 1)
        guard case let .content(_, refreshedAt, itemCount) =
            store.appleHealthTimelineState else {
            Issue.record(
                "Expected content, got \(store.appleHealthTimelineState)"
            )
            return
        }
        #expect(refreshedAt == now)
        #expect(itemCount == 1)
    }

    @Test @MainActor
    func hidingTimelineDiscardsAnInFlightSampleResult() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = StubAppleHealthReader(
            batch: .empty,
            suspendsSamples: true
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: true
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences
        )
        let refresh = Task { @MainActor in
            await store.refreshAppleHealthTimelineIfEnabled(now: now)
        }

        for _ in 0..<20 where reader.sampleRequestIntervals.isEmpty {
            await Task.yield()
        }
        #expect(reader.sampleRequestIntervals.count == 1)

        store.hideAppleHealthFromTimeline()
        reader.resumeSamples()
        await refresh.value

        #expect(reader.authorizationRequestCount == 0)
        #expect(preferences.isTimelineEnabled == false)
        #expect(store.isAppleHealthTimelineEnabled == false)
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(store.appleHealthTimelineState == .disabled)
    }

    @Test @MainActor
    func noReadableSamplesStillCreateTheCompleteStaticTemplateCatalog()
        async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try makeTestContext()
        let stateDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HealthCatalogEmpty-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        let reader = StubAppleHealthReader(batch: .empty)
        let preferences = StubAppleHealthTimelinePreferences(isTimelineEnabled: false)
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences,
            writeAuthorization: .isolatedTestHarness,
            syncConflictService: SyncConflictService(
                stateURL: stateDirectory.appending(path: "state.json")
            )
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.hasCompletedStartupConfiguration = true

        await store.showAppleHealthInTimeline(now: now)

        guard case .noReadableData = store.appleHealthTimelineState else {
            Issue.record("Expected noReadableData, got \(store.appleHealthTimelineState)")
            return
        }
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(preferences.isTimelineEnabled)
        let staticPlan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        #expect(
            Set(store.tasks.map(\.id)) ==
                Set(staticPlan.tasks.map(\.id))
        )
        #expect(
            Set(store.taskCategories.map(\.id)) ==
                Set(staticPlan.categories.map(\.id))
        )
        #expect(
            Set(store.taskCategoryAssignments.map(\.id)) ==
                Set(staticPlan.tasks.map(\.categoryAssignmentID))
        )
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test @MainActor
    func clearRecoveryIdentityReceiptRoundTripsOnlyThroughLocalPreferences()
        throws {
        let suiteName = "AppleHealthClearRecovery-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer {
            defaults.removePersistentDomain(forName: suiteName)
        }
        let firstID = try fixedID(28)
        let secondID = try fixedID(29)
        let writer = UserDefaultsAppleHealthTimelinePreferenceStore(
            defaults: defaults
        )

        writer.taskCatalogClearRecoveryTaskIDs = [secondID, firstID]

        let reader = UserDefaultsAppleHealthTimelinePreferenceStore(
            defaults: defaults
        )
        #expect(
            reader.taskCatalogClearRecoveryTaskIDs == [firstID, secondID]
        )
        reader.taskCatalogClearRecoveryTaskIDs = []
        #expect(reader.taskCatalogClearRecoveryTaskIDs.isEmpty)
    }

    @Test @MainActor
    func enablingCreatesStaticEditableTemplatesWithoutPersistingHealthRecords()
        async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try makeTestContext()
        let stateDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HealthCatalogFacade-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        let reader = StubAppleHealthReader(
            batch: AppleHealthSampleBatch(
                workouts: [
                    workout(
                        id: try fixedID(30),
                        kind: .running,
                        start: now.timeIntervalSince1970 - 1_800,
                        end: now.timeIntervalSince1970 - 1_200
                    ),
                ],
                sleep: [
                    sleep(
                        id: try fixedID(31),
                        stage: .asleepCore,
                        start: now.timeIntervalSince1970 - 3_600,
                        end: now.timeIntervalSince1970 - 2_400
                    ),
                ]
            )
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: false
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences,
            writeAuthorization: .isolatedTestHarness,
            syncConflictService: SyncConflictService(
                stateURL: stateDirectory.appending(path: "state.json")
            )
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.hasCompletedStartupConfiguration = true

        await store.showAppleHealthInTimeline(now: now)

        let running = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        let sleep = AppleHealthTaskCatalog.taskDefinition(for: .sleep)
        let staticPlan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        #expect(
            Set(store.tasks.map(\.id)) ==
                Set(staticPlan.tasks.map(\.id))
        )
        #expect(
            Set(store.taskCategories.map(\.id)) ==
                Set(staticPlan.categories.map(\.id))
        )
        #expect(store.appleHealthTimelineItems.count == 2)
        #expect(store.appleHealthTaskCatalogErrorMessage == nil)
        #expect(preferences.taskCatalogClearRecoveryTaskIDs.isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)

        store.hideAppleHealthFromTimeline()
        #expect(store.task(for: running.id) != nil)
        #expect(store.task(for: sleep.id) != nil)
    }

    @Test @MainActor
    func enabledRefreshRetriesAndConsumesOnlyConfirmedClearRecovery()
        async throws {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let context = try makeTestContext()
        let running = AppleHealthTaskCatalog.taskDefinition(
            for: .workout(.running)
        )
        _ = try StoreScopedAppleHealthTaskCatalogCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "health-refresh-recovery"
        ).apply(roles: [.workout(.running)])
        try context.performAtomicMutation {
            try SeedData.clearAllChanges(
                context: context,
                includesPreferences: true
            )
        }
        let stateDirectory = FileManager.default.temporaryDirectory
            .appending(path: "HealthCatalogRefresh-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: stateDirectory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: stateDirectory)
        }
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: true
        )
        preferences.taskCatalogClearRecoveryTaskIDs = [running.id]
        let store = TimeTrackerStore(
            appleHealthDataReader: StubAppleHealthReader(batch: .empty),
            appleHealthTimelinePreferenceStore: preferences,
            writeAuthorization: .isolatedTestHarness,
            syncConflictService: SyncConflictService(
                stateURL: stateDirectory.appending(path: "state.json")
            )
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.hasCompletedStartupConfiguration = true

        await store.refreshAppleHealthTimeline(now: now)

        #expect(store.task(for: running.id) != nil)
        #expect(preferences.taskCatalogClearRecoveryTaskIDs.isEmpty)
        let assignment = try #require(
            try context.fetch(FetchDescriptor<TaskCategoryAssignment>())
                .logicalWinnersByTaskID()[running.id]
        )
        #expect(assignment.id == running.categoryAssignmentID)
        #expect(assignment.categoryID == running.categoryID)
    }

    @Test
    func healthTimelineUIUsesSharedChartAndRoutesThroughStaticTemplates()
        throws {
        let home = try sourceText(
            "timetracker/Features/Home/Sections/HomeTimelineViews.swift"
        )
        let phone = try sourceText(
            "timetracker/Features/Home/PhoneHomeSections.swift"
        )
        let sharedLegend = try sourceText(
            "timetracker/SharedUI/Components/TimelineLegendRow.swift"
        )
        let healthUI = try sourceText(
            "timetracker/Features/Home/Rows/HomeAppleHealthTimelineRows.swift"
        )
        let entryRow = try sourceText(
            "timetracker/Features/Home/Rows/TodayTimelineEntryRow.swift"
        )
        let readyBranch = try #require(
            healthUI.slice(
                from: "case .ready:",
                to: "case .noReadableData:"
            )
        )

        #expect(home.contains("TimelineChart("))
        #expect(home.contains("TodayTimelineEntryRow("))
        #expect(phone.contains("TodayTimelineEntryRow("))
        #expect(entryRow.contains("TimelineLegendRow(entry: entry)"))
        #expect(entryRow.contains("TimelineRow("))
        #expect(entryRow.contains("appleHealthGeneratedTaskID"))
        #expect(entryRow.contains("openTaskDetail(taskID)"))
        #expect(sharedLegend.contains("struct TimelineLegendRow"))
        #expect(healthUI.contains("showAppleHealthInTimeline"))
        #expect(readyBranch.contains("refreshAppleHealthTimeline()"))
        #expect(readyBranch.contains("showAppleHealthInTimeline()") == false)
        #expect(healthUI.contains("TaskNode(") == false)
        #expect(healthUI.contains("TimeSegment(") == false)
    }

    @Test
    func healthRefreshDoesNotGateCoreStartupRouting() throws {
        let content = try sourceText("timetracker/App/ContentView.swift")
        let readiness = try #require(
            content.range(of: "hasFinishedInitialConfiguration = true")
        )
        let deepLinks = try #require(
            content.range(of: "drainPendingDeepLinks()")
        )
        let watchRegistration = try #require(
            content.range(of: "registerForWatchCommandsIfNeeded()")
        )
        let healthRefresh = try #require(
            content.range(
                of: "await store.refreshAppleHealthTimelineIfEnabled()"
            )
        )

        #expect(readiness.lowerBound < healthRefresh.lowerBound)
        #expect(deepLinks.lowerBound < healthRefresh.lowerBound)
        #expect(watchRegistration.lowerBound < healthRefresh.lowerBound)
        #expect(content.contains(".NSCalendarDayChanged"))

        let recovery = try #require(
            content.slice(
                from: ".onChange(of: store.persistenceWriteSafety)",
                to: ".onOpenURL"
            )
        )
        let recoveryDeepLinks = try #require(
            recovery.range(of: "drainPendingDeepLinks()")
        )
        let recoveryWatchRegistration = try #require(
            recovery.range(of: "registerForWatchCommandsIfNeeded()")
        )
        let recoveryHealthRefresh = try #require(
            recovery.range(
                of: "await store.refreshAppleHealthTimelineIfEnabled()"
            )
        )

        #expect(
            recovery.contains(
                "guard hasFinishedInitialConfiguration == false else { return }"
            )
        )
        #expect(recoveryDeepLinks.lowerBound < recoveryHealthRefresh.lowerBound)
        #expect(
            recoveryWatchRegistration.lowerBound
                < recoveryHealthRefresh.lowerBound
        )
    }

    private func workout(
        id: UUID,
        kind: AppleHealthWorkoutKind,
        start: TimeInterval,
        end: TimeInterval,
        source: String = "test"
    ) -> AppleHealthWorkoutSample {
        AppleHealthWorkoutSample(
            id: id,
            kind: kind,
            startedAt: Date(timeIntervalSince1970: start),
            endedAt: Date(timeIntervalSince1970: end),
            sourceBundleIdentifier: source
        )
    }

    private func sleep(
        id: UUID,
        stage: AppleHealthSleepStage,
        start: TimeInterval,
        end: TimeInterval,
        source: String = "test"
    ) -> AppleHealthSleepSample {
        AppleHealthSleepSample(
            id: id,
            stage: stage,
            startedAt: Date(timeIntervalSince1970: start),
            endedAt: Date(timeIntervalSince1970: end),
            sourceBundleIdentifier: source
        )
    }

    private func fixedID(_ suffix: Int) throws -> UUID {
        try #require(
            UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    suffix
                )
            )
        )
    }
}

@MainActor
private final class StubAppleHealthReader: AppleHealthDataReading {
    let isHealthDataAvailable: Bool
    var authorizationRequestCount = 0
    var sampleRequestIntervals: [DateInterval] = []
    var batch: AppleHealthSampleBatch
    var authorizationError: Error?
    var sampleError: Error?
    var suspendsSamples: Bool
    private var sampleContinuation:
        CheckedContinuation<AppleHealthSampleBatch, Never>?

    init(
        isHealthDataAvailable: Bool = true,
        batch: AppleHealthSampleBatch,
        suspendsSamples: Bool = false
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.batch = batch
        self.suspendsSamples = suspendsSamples
    }

    func requestReadAuthorization() async throws {
        authorizationRequestCount += 1
        if let authorizationError {
            throw authorizationError
        }
    }

    func samples(overlapping interval: DateInterval) async throws -> AppleHealthSampleBatch {
        sampleRequestIntervals.append(interval)
        if let sampleError {
            throw sampleError
        }
        if suspendsSamples {
            return await withCheckedContinuation { continuation in
                sampleContinuation = continuation
            }
        }
        return batch
    }

    func resumeSamples() {
        sampleContinuation?.resume(returning: batch)
        sampleContinuation = nil
    }
}

@MainActor
private final class StubAppleHealthTimelinePreferences:
    AppleHealthTimelinePreferenceStoring {
    var isTimelineEnabled: Bool
    var taskCatalogClearRecoveryTaskIDs: Set<UUID> = []

    init(isTimelineEnabled: Bool) {
        self.isTimelineEnabled = isTimelineEnabled
    }
}
