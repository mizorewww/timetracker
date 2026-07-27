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
    func projectionBuildsOneEpisodeAcrossSameSourceStagesAndExcludesAwakeDuration()
        throws
    {
        let service = AppleHealthTimelineProjectionService()
        let bounds = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 3000)
        )
        let firstID = try fixedID(1)
        let secondID = try fixedID(2)
        let thirdID = try fixedID(3)
        let separateID = try fixedID(4)
        let samples = [
            sleep(id: UUID(), stage: .inBed, start: 0, end: 1800, source: "watch"),
            sleep(id: UUID(), stage: .awake, start: 300, end: 600, source: "watch"),
            sleep(id: firstID, stage: .asleepCore, start: 100, end: 300, source: "watch"),
            sleep(id: secondID, stage: .asleepDeep, start: 600, end: 900, source: "watch"),
            sleep(id: thirdID, stage: .asleepREM, start: 900, end: 1200, source: "watch"),
            sleep(id: separateID, stage: .asleepUnspecified, start: 2400, end: 2600, source: "watch"),
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
                end: Date(timeIntervalSince1970: 1200)
            ),
            DateInterval(
                start: Date(timeIntervalSince1970: 2400),
                end: Date(timeIntervalSince1970: 2600)
            ),
        ])
        #expect(forward.first?.id == .appleHealthSleep(firstID))
        #expect(forward.last?.id == .appleHealthSleep(separateID))
        #expect(forward.first?.durationIntervals == [
            DateInterval(
                start: Date(timeIntervalSince1970: 100),
                end: Date(timeIntervalSince1970: 300)
            ),
            DateInterval(
                start: Date(timeIntervalSince1970: 600),
                end: Date(timeIntervalSince1970: 1200)
            ),
        ])
    }

    @Test
    func projectionClipsCrossMidnightEpisodeAfterGroupingAndKeepsRawAnchor()
        throws
    {
        let service = AppleHealthTimelineProjectionService()
        let bounds = DateInterval(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 200)
        )
        let anchorID = try fixedID(5)
        let samples = [
            sleep(id: anchorID, stage: .asleepCore, start: 50, end: 90),
            sleep(id: UUID(), stage: .awake, start: 90, end: 110),
            sleep(id: UUID(), stage: .asleepREM, start: 110, end: 180),
            sleep(id: UUID(), stage: .asleepREM, start: 200, end: 250, source: "other"),
            sleep(id: UUID(), stage: .asleepREM, start: 170, end: 170),
        ]

        let items = service.project(
            batch: AppleHealthSampleBatch(workouts: [], sleep: samples),
            visibleInterval: bounds
        )

        #expect(items.count == 1)
        #expect(items.first?.id == .appleHealthSleep(anchorID))
        #expect(items.first?.interval ==
            DateInterval(
                start: Date(timeIntervalSince1970: 100),
                end: Date(timeIntervalSince1970: 180)
            ))
        #expect(items.first?.durationIntervals == [
            DateInterval(
                start: Date(timeIntervalSince1970: 110),
                end: Date(timeIntervalSince1970: 180)
            ),
        ])
    }

    @Test
    func projectionUsesGapEvidenceButNeverJoinsDifferentSources() throws {
        let service = AppleHealthTimelineProjectionService()
        let bounds = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 4000)
        )
        let firstID = try fixedID(6)
        let secondID = try fixedID(7)
        let otherSourceID = try fixedID(8)
        let items = service.project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    sleep(
                        id: firstID,
                        stage: .asleepCore,
                        start: 0,
                        end: 600,
                        source: "health",
                        productType: "watch"
                    ),
                    sleep(
                        id: UUID(),
                        stage: .awake,
                        start: 600,
                        end: 2500,
                        source: "health",
                        productType: "watch"
                    ),
                    sleep(
                        id: secondID,
                        stage: .asleepREM,
                        start: 2500,
                        end: 3000,
                        source: "health",
                        productType: "watch"
                    ),
                    sleep(
                        id: otherSourceID,
                        stage: .asleepUnspecified,
                        start: 3000,
                        end: 3600,
                        source: "health",
                        productType: "phone"
                    ),
                ]
            ),
            visibleInterval: bounds
        )

        #expect(items.map(\.id) == [
            .appleHealthSleep(firstID),
            .appleHealthSleep(secondID),
            .appleHealthSleep(otherSourceID),
        ])
    }

    @Test
    func projectionUsesInBedOnlyAsShortGapEvidenceWithoutExpandingBounds()
        throws
    {
        let service = AppleHealthTimelineProjectionService()
        let firstID = try fixedID(11)
        let items = try service.project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    sleep(id: UUID(), stage: .inBed, start: 0, end: 700),
                    sleep(id: firstID, stage: .asleepCore, start: 100, end: 200),
                    sleep(id: fixedID(12), stage: .asleepREM, start: 500, end: 600),
                ]
            ),
            visibleInterval: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 1000)
            )
        )

        #expect(items.count == 1)
        #expect(items.first?.interval == DateInterval(
            start: Date(timeIntervalSince1970: 100),
            end: Date(timeIntervalSince1970: 600)
        ))
        #expect(items.first?.durationIntervals.map(\.duration) == [100, 100])
    }

    @Test
    func projectionHonorsUnlabeledAndInBedGapBoundaries() throws {
        let service = AppleHealthTimelineProjectionService()
        let items = try service.project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    sleep(id: fixedID(30), stage: .asleepCore, start: 0, end: 100),
                    sleep(id: fixedID(31), stage: .asleepREM, start: 220, end: 300),
                    sleep(id: fixedID(32), stage: .asleepCore, start: 421, end: 500),
                    sleep(id: UUID(), stage: .inBed, start: 500, end: 1101),
                    sleep(id: fixedID(33), stage: .asleepREM, start: 1101, end: 1200),
                ]
            ),
            visibleInterval: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 2000)
            )
        )

        #expect(items.map(\.interval) == [
            DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 300)
            ),
            DateInterval(
                start: Date(timeIntervalSince1970: 421),
                end: Date(timeIntervalSince1970: 500)
            ),
            DateInterval(
                start: Date(timeIntervalSince1970: 1101),
                end: Date(timeIntervalSince1970: 1200)
            ),
        ])
    }

    @Test
    func projectionUnionsOverlappingFractionalAsleepIntervalsBeforeRounding()
        throws
    {
        let service = AppleHealthTimelineProjectionService()
        let anchorID = try fixedID(34)
        let item = try #require(
            try service.project(
                batch: AppleHealthSampleBatch(
                    workouts: [],
                    sleep: [
                        sleep(id: anchorID, stage: .asleepCore, start: 100.2, end: 400.8),
                        sleep(id: fixedID(35), stage: .asleepDeep, start: 250.4, end: 500.9),
                    ]
                ),
                visibleInterval: DateInterval(
                    start: Date(timeIntervalSince1970: 0),
                    end: Date(timeIntervalSince1970: 1000)
                )
            ).first
        )
        let entry = try #require(
            AnalyticsTimelineSnapshotService().snapshot(
                seeds: [
                    TimelinePresentationSeed(
                        id: item.id,
                        subject: item.subject,
                        title: "Sleep",
                        path: "Daily",
                        iconName: "bed.double.fill",
                        colorHex: "5856D6",
                        interval: item.interval,
                        durationIntervals: item.durationIntervals
                    ),
                ],
                visibleInterval: DateInterval(
                    start: Date(timeIntervalSince1970: 0),
                    end: Date(timeIntervalSince1970: 1000)
                )
            ).entries.first
        )

        #expect(item.id == .appleHealthSleep(anchorID))
        #expect(item.durationIntervals.count == 1)
        #expect(entry.durationSeconds == 400)
    }

    @Test
    func projectionCapsAnEpisodeEvenWhenLongSamplesTouch() throws {
        let service = AppleHealthTimelineProjectionService()
        let firstID = try fixedID(36)
        let secondID = try fixedID(37)
        let items = service.project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    sleep(
                        id: firstID,
                        stage: .asleepCore,
                        start: 0,
                        end: 17 * 3600
                    ),
                    sleep(
                        id: secondID,
                        stage: .asleepREM,
                        start: 17 * 3600,
                        end: 19 * 3600
                    ),
                ]
            ),
            visibleInterval: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 20 * 3600)
            )
        )

        #expect(items.map(\.id) == [
            .appleHealthSleep(firstID),
            .appleHealthSleep(secondID),
        ])
    }

    @Test
    func projectionRejectsSingleAsleepSamplesBeyondTheEpisodeLimit() throws {
        let items = try AppleHealthTimelineProjectionService().project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    sleep(
                        id: fixedID(38),
                        stage: .asleepUnspecified,
                        start: 0,
                        end: 19 * 3600
                    ),
                ]
            ),
            visibleInterval: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 20 * 3600)
            )
        )

        #expect(items.isEmpty)
    }

    @Test
    func projectionKeepsAFullSourceWhenDetailedStagesCoverOnlyHalfTheSleep()
        throws
    {
        let fullID = try fixedID(39)
        let partialID = try fixedID(40)
        let items = AppleHealthTimelineProjectionService().project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    sleep(
                        id: fullID,
                        stage: .asleepUnspecified,
                        start: 0,
                        end: 8 * 3600,
                        source: "phone"
                    ),
                    sleep(
                        id: partialID,
                        stage: .asleepCore,
                        start: 4 * 3600,
                        end: 8 * 3600,
                        source: "watch"
                    ),
                ]
            ),
            visibleInterval: DateInterval(
                start: Date(timeIntervalSince1970: 0),
                end: Date(timeIntervalSince1970: 9 * 3600)
            )
        )

        #expect(items.map(\.id) == [
            .appleHealthSleep(fullID),
            .appleHealthSleep(partialID),
        ])
    }

    @Test
    func projectionDeduplicatesOverlappingSourcesAndKeepsStableEpisodeID()
        throws
    {
        let service = AppleHealthTimelineProjectionService()
        let anchorID = try fixedID(13)
        let initial = try [
            sleep(id: fixedID(16), stage: .asleepUnspecified, start: 90, end: 620, source: "phone"),
            sleep(id: anchorID, stage: .asleepCore, start: 100, end: 300, source: "watch"),
            sleep(id: fixedID(14), stage: .asleepDeep, start: 300, end: 550, source: "watch"),
        ]
        let bounds = DateInterval(
            start: Date(timeIntervalSince1970: 0),
            end: Date(timeIntervalSince1970: 1000)
        )

        let before = service.project(
            batch: AppleHealthSampleBatch(workouts: [], sleep: initial),
            visibleInterval: bounds
        )
        let after = try service.project(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: initial + [
                    sleep(id: fixedID(15), stage: .asleepREM, start: 550, end: 600, source: "watch"),
                ]
            ),
            visibleInterval: bounds
        )

        #expect(before.count == 1)
        #expect(after.count == 1)
        #expect(before.first?.id == .appleHealthSleep(anchorID))
        #expect(after.first?.id == before.first?.id)
        #expect(after.first?.durationIntervals.map(\.duration) == [500])
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
    func timelineSnapshotUsesEpisodeEnvelopeForLayoutButOnlyAsleepIntervalsForDuration()
        throws
    {
        let anchorID = try fixedID(17)
        let seed = TimelinePresentationSeed(
            id: .appleHealthSleep(anchorID),
            subject: .appleHealthSleep,
            title: "Sleep",
            path: "Daily",
            iconName: "bed.double.fill",
            colorHex: "5856D6",
            interval: DateInterval(
                start: Date(timeIntervalSince1970: 100),
                end: Date(timeIntervalSince1970: 500)
            ),
            durationIntervals: [
                DateInterval(
                    start: Date(timeIntervalSince1970: 100),
                    end: Date(timeIntervalSince1970: 200)
                ),
                DateInterval(
                    start: Date(timeIntervalSince1970: 300),
                    end: Date(timeIntervalSince1970: 500)
                ),
            ]
        )

        let snapshot = AnalyticsTimelineSnapshotService().snapshot(
            seeds: [seed],
            visibleInterval: DateInterval(
                start: Date(timeIntervalSince1970: 150),
                end: Date(timeIntervalSince1970: 450)
            )
        )
        let entry = try #require(snapshot.entries.first)

        #expect(entry.interval == DateInterval(
            start: Date(timeIntervalSince1970: 150),
            end: Date(timeIntervalSince1970: 450)
        ))
        #expect(entry.durationSeconds == 200)
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
                        startedAt: now.addingTimeInterval(-1800),
                        endedAt: now.addingTimeInterval(-1200),
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
        #expect(reader.authorizationRequestStatusCount == 0)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.isEmpty)

        await store.showAppleHealthInTimeline(now: now, calendar: calendar)

        #expect(reader.authorizationRequestStatusCount == 0)
        #expect(reader.authorizationRequestCount == 1)
        #expect(reader.sampleRequestIntervals.count == 1)
        let visibleInterval = DateInterval(
            start: calendar.startOfDay(for: now),
            end: now
        )
        #expect(
            reader.sampleRequestIntervals.first?.start
                == visibleInterval.start.addingTimeInterval(
                    -AppleHealthSleepEpisodePolicy.queryContextDuration
                )
        )
        #expect(reader.sampleRequestIntervals.first?.end == now)
        #expect(preferences.isTimelineEnabled)
        #expect(store.appleHealthTimelineItems.count == 1)
        #expect(
            store.appleHealthTimelineState == .content(
                interval: visibleInterval,
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
    func disabledTimelineRefreshMaterializesVisibleSyncOnlyCatalogWithoutHealthAccess()
        async throws
    {
        let context = try makeTestContext()
        let reader = StubAppleHealthReader(
            isHealthDataAvailable: false,
            batch: .empty
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: false
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences,
            writeAuthorization: .isolatedTestHarness
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.hasCompletedStartupConfiguration = true

        await store.refreshAppleHealthTimelineIfEnabled()

        let plan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        #expect(Set(store.tasks.map(\.id)) == Set(plan.tasks.map(\.id)))
        #expect(
            Set(store.taskCategories.map(\.id)) == Set(plan.categories.map(\.id))
        )
        #expect(
            Set(store.taskCategoryAssignments.map(\.id)) ==
                Set(plan.tasks.map(\.categoryAssignmentID))
        )
        for definition in plan.tasks {
            let task = try #require(store.task(for: definition.id))
            #expect(store.isTaskVisible(task))
            #expect(store.isTaskAvailableForTracking(task) == false)
        }
        #expect(preferences.isTimelineEnabled == false)
        #expect(store.appleHealthTimelineState == .unavailable)
        #expect(reader.authorizationRequestStatusCount == 0)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)
    }

    @Test @MainActor
    func existingCatalogConvergesAStaleFacadeAfterNoOpReconciliation()
        async throws
    {
        let context = try makeTestContext()
        let reader = StubAppleHealthReader(
            isHealthDataAvailable: false,
            batch: .empty
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: false
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences,
            writeAuthorization: .isolatedTestHarness
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.hasCompletedStartupConfiguration = true

        let plan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        _ = try StoreScopedAppleHealthTaskCatalogCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "remote-scene"
        ).apply(roles: AppleHealthTaskCatalog.allRoles)

        #expect(store.tasks.isEmpty)
        #expect(store.taskCategories.isEmpty)
        #expect(store.taskCategoryAssignments.isEmpty)

        await store.refreshAppleHealthTimelineIfEnabled()

        let expectedTaskIDs = Set(plan.tasks.map(\.id))
        #expect(Set(store.tasks.map(\.id)) == expectedTaskIDs)
        #expect(
            Set(store.taskCategories.map(\.id)) ==
                Set(plan.categories.map(\.id))
        )
        #expect(
            Set(store.taskCategoryAssignments.map(\.id)) ==
                Set(plan.tasks.map(\.categoryAssignmentID))
        )
        #expect(
            Set(
                store.taskTreeSections(expandedTaskIDs: [])
                    .flatMap(\.rows)
                    .map(\.taskID)
            ) == expectedTaskIDs
        )
        for definition in plan.tasks {
            let title = AppStrings.localized(
                definition.titleLocalizationKey
            )
            #expect(
                store.taskSearchResults(matching: title)
                    .contains { $0.id == definition.id }
            )
        }
        #expect(reader.authorizationRequestStatusCount == 0)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.isEmpty)
    }

    @Test @MainActor
    func remoteClearTombstonesRestoreCatalogWithoutDeviceLocalReceipt()
        async throws
    {
        let context = try makeTestContext()
        _ = try StoreScopedAppleHealthTaskCatalogCommandCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "catalog-origin"
        ).apply(roles: AppleHealthTaskCatalog.allRoles)
        try context.performAtomicMutation {
            try SeedData.clearAllChanges(
                context: context,
                includesPreferences: true
            )
        }

        let reader = StubAppleHealthReader(
            isHealthDataAvailable: false,
            batch: .empty
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: false
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences,
            writeAuthorization: .isolatedTestHarness
        )
        store.configureRepositoriesIfNeeded(context: context)
        store.hasCompletedStartupConfiguration = true

        #expect(store.tasks.isEmpty)
        #expect(preferences.taskCatalogClearRecoveryTaskIDs.isEmpty)

        await store.refreshAppleHealthTimelineIfEnabled()

        let plan = AppleHealthTaskCatalog.plan(
            for: AppleHealthTaskCatalog.allRoles
        )
        #expect(Set(store.tasks.map(\.id)) == Set(plan.tasks.map(\.id)))
        #expect(
            Set(store.taskCategories.map(\.id)) ==
                Set(plan.categories.map(\.id))
        )
        #expect(
            Set(store.taskCategoryAssignments.map(\.id)) ==
                Set(plan.tasks.map(\.categoryAssignmentID))
        )
        #expect(preferences.taskCatalogClearRecoveryTaskIDs.isEmpty)
        #expect(reader.authorizationRequestStatusCount == 0)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.isEmpty)
    }

    @Test @MainActor
    func enabledRefreshMergesCrossMidnightSleepBeforeVisibleRangeClipping()
        async throws
    {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let dayStart = try #require(
            calendar.date(
                from: DateComponents(year: 2026, month: 7, day: 22)
            )
        )
        let now = dayStart.addingTimeInterval(3600)
        let coreID = try fixedID(41)
        let reader = try StubAppleHealthReader(
            batch: AppleHealthSampleBatch(
                workouts: [],
                sleep: [
                    AppleHealthSleepSample(
                        id: coreID,
                        stage: .asleepCore,
                        startedAt: dayStart.addingTimeInterval(-1800),
                        endedAt: dayStart.addingTimeInterval(-120),
                        sourceBundleIdentifier: "test.sleep",
                        sourceProductType: "watch"
                    ),
                    AppleHealthSleepSample(
                        id: fixedID(42),
                        stage: .awake,
                        startedAt: dayStart.addingTimeInterval(-120),
                        endedAt: dayStart.addingTimeInterval(300),
                        sourceBundleIdentifier: "test.sleep",
                        sourceProductType: "watch"
                    ),
                    AppleHealthSleepSample(
                        id: fixedID(43),
                        stage: .asleepREM,
                        startedAt: dayStart.addingTimeInterval(300),
                        endedAt: dayStart.addingTimeInterval(2400),
                        sourceBundleIdentifier: "test.sleep",
                        sourceProductType: "watch"
                    ),
                ]
            )
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore:
            StubAppleHealthTimelinePreferences(isTimelineEnabled: true)
        )

        await store.refreshAppleHealthTimelineIfEnabled(
            now: now,
            calendar: calendar
        )

        let visibleInterval = DateInterval(start: dayStart, end: now)
        #expect(reader.sampleRequestIntervals == [
            DateInterval(
                start: dayStart.addingTimeInterval(
                    -AppleHealthSleepEpisodePolicy.queryContextDuration
                ),
                end: now
            ),
        ])
        let item = try #require(store.appleHealthTimelineItems.first)
        #expect(store.appleHealthTimelineItems.count == 1)
        #expect(item.id == .appleHealthSleep(coreID))
        #expect(item.interval == DateInterval(
            start: dayStart,
            end: dayStart.addingTimeInterval(2400)
        ))
        #expect(item.durationIntervals == [
            DateInterval(
                start: dayStart.addingTimeInterval(300),
                end: dayStart.addingTimeInterval(2400)
            ),
        ])
        #expect(
            store.appleHealthTimelineState == .content(
                interval: visibleInterval,
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
        let entry = try #require(timeline.entries.first)
        #expect(timeline.entries.count == 1)
        #expect(entry.subject == .appleHealthSleep)
        #expect(entry.startedAt == dayStart)
        #expect(entry.endedAt == dayStart.addingTimeInterval(2400))
        #expect(entry.durationSeconds == 2100)
    }

    @Test @MainActor
    func enabledAutomaticRefreshReauthorizesBeforeReadingWhenNoSheetIsNeeded()
        async throws
    {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let reader = try StubAppleHealthReader(
            batch: AppleHealthSampleBatch(
                workouts: [
                    AppleHealthWorkoutSample(
                        id: fixedID(21),
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

        #expect(reader.authorizationRequestStatusCount == 1)
        #expect(reader.authorizationRequestCount == 1)
        #expect(reader.sampleRequestIntervals.count == 1)
        #expect(store.appleHealthTimelineItems.count == 1)
        guard case let .content(_, refreshedAt, itemCount) =
            store.appleHealthTimelineState
        else {
            Issue.record(
                "Expected content, got \(store.appleHealthTimelineState)"
            )
            return
        }
        #expect(refreshedAt == now)
        #expect(itemCount == 1)
    }

    @Test @MainActor
    func automaticRefreshWaitsForContextBeforePresentingAuthorizationSheet()
        async
    {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = StubAppleHealthReader(
            batch: .empty,
            requestStatus: .shouldRequest
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: true
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences
        )

        await store.refreshAppleHealthTimelineIfEnabled(now: now)

        #expect(reader.authorizationRequestStatusCount == 1)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.isEmpty)
        #expect(store.appleHealthTimelineState == .ready)

        await store.refreshAppleHealthTimeline(now: now)

        #expect(reader.authorizationRequestStatusCount == 1)
        #expect(reader.authorizationRequestCount == 1)
        #expect(reader.sampleRequestIntervals.count == 1)
        guard case .noReadableData = store.appleHealthTimelineState else {
            Issue.record(
                "Expected noReadableData, got \(store.appleHealthTimelineState)"
            )
            return
        }
    }

    @Test @MainActor
    func unknownAutomaticAuthorizationStatusClearsStaleHealthContent()
        async
    {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = StubAppleHealthReader(
            batch: .empty,
            requestStatus: .unknown
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: true
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences
        )
        store.appleHealthTimelineItems = [
            AppleHealthTimelineItem(
                id: .appleHealthWorkout(UUID()),
                subject: .appleHealthWorkout(.walking),
                interval: DateInterval(
                    start: now.addingTimeInterval(-60),
                    end: now
                )
            ),
        ]

        await store.refreshAppleHealthTimelineIfEnabled(now: now)

        #expect(reader.authorizationRequestStatusCount == 1)
        #expect(reader.authorizationRequestCount == 0)
        #expect(reader.sampleRequestIntervals.isEmpty)
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(
            store.appleHealthTimelineState == .failed(
                AppleHealthReadError.authorizationRequestStatusUnavailable
                    .localizedDescription
            )
        )
    }

    @Test @MainActor
    func hidingTimelineCancelsAnInFlightSampleRequest() async {
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

        for _ in 0 ..< 20 where reader.sampleRequestIntervals.isEmpty {
            await Task.yield()
        }
        #expect(reader.sampleRequestIntervals.count == 1)

        store.hideAppleHealthFromTimeline()
        await refresh.value

        #expect(reader.authorizationRequestStatusCount == 1)
        #expect(reader.authorizationRequestCount == 1)
        #expect(reader.sampleCancellationCount == 1)
        #expect(preferences.isTimelineEnabled == false)
        #expect(store.isAppleHealthTimelineEnabled == false)
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(store.appleHealthTimelineState == .disabled)
    }

    @Test @MainActor
    func newerRefreshCancelsOlderHealthQueryAndKeepsTheNewestResult()
        async throws
    {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = try StubAppleHealthReader(
            batch: AppleHealthSampleBatch(
                workouts: [
                    workout(
                        id: fixedID(41),
                        kind: .running,
                        start: now.timeIntervalSince1970 - 600,
                        end: now.timeIntervalSince1970 - 300
                    ),
                ],
                sleep: []
            ),
            suspendsSamples: true
        )
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: true
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences
        )
        let olderRefresh = Task { @MainActor in
            await store.refreshAppleHealthTimelineIfEnabled(now: now)
        }
        for _ in 0 ..< 20 where reader.sampleRequestIntervals.isEmpty {
            await Task.yield()
        }
        #expect(reader.sampleRequestIntervals.count == 1)

        await store.refreshAppleHealthTimelineIfEnabled(now: now)
        await olderRefresh.value

        #expect(reader.authorizationRequestStatusCount == 2)
        #expect(reader.authorizationRequestCount == 2)
        #expect(reader.sampleRequestIntervals.count == 2)
        #expect(reader.sampleCancellationCount == 1)
        #expect(
            store.appleHealthTimelineItems.map(\.subject) == [
                .appleHealthWorkout(.running),
            ]
        )
        guard case let .content(_, _, itemCount) =
            store.appleHealthTimelineState
        else {
            Issue.record(
                "Expected content, got \(store.appleHealthTimelineState)"
            )
            return
        }
        #expect(itemCount == 1)
    }

    @Test @MainActor
    func cancelledAuthorizationReturnsToReviewStateWithoutQuerying() async {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let reader = StubAppleHealthReader(batch: .empty)
        reader.authorizationError = CancellationError()
        let preferences = StubAppleHealthTimelinePreferences(
            isTimelineEnabled: true
        )
        let store = TimeTrackerStore(
            appleHealthDataReader: reader,
            appleHealthTimelinePreferenceStore: preferences
        )

        await store.refreshAppleHealthTimeline(now: now)

        #expect(reader.authorizationRequestCount == 1)
        #expect(reader.sampleRequestIntervals.isEmpty)
        #expect(store.appleHealthTimelineItems.isEmpty)
        #expect(store.appleHealthTimelineState == .ready)
    }

    @Test @MainActor
    func noReadableSamplesStillCreateTheCompleteStaticTemplateCatalog()
        async throws
    {
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
        throws
    {
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
    func enablingCreatesSyncOnlyTaskLabelsWithoutPersistingHealthRecords()
        async throws
    {
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
        let reader = try StubAppleHealthReader(
            batch: AppleHealthSampleBatch(
                workouts: [
                    workout(
                        id: fixedID(30),
                        kind: .running,
                        start: now.timeIntervalSince1970 - 1800,
                        end: now.timeIntervalSince1970 - 1200
                    ),
                ],
                sleep: [
                    sleep(
                        id: fixedID(31),
                        stage: .asleepCore,
                        start: now.timeIntervalSince1970 - 3600,
                        end: now.timeIntervalSince1970 - 2400
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
        #expect(try store.isTaskVisible(#require(store.task(for: running.id))))
        #expect(
            try store.isTaskAvailableForTracking(
                #require(store.task(for: running.id))
            ) == false
        )
        #expect(try store.isTaskVisible(#require(store.task(for: sleep.id))))
        #expect(
            try store.isTaskAvailableForTracking(
                #require(store.task(for: sleep.id))
            ) == false
        )
        store.preferences.quickStartTaskIDs = [running.id, sleep.id]
        #expect(TodayHomeContent(store: store).quickStartTasks.isEmpty)
        #expect(store.startTask(taskID: running.id) == false)
        #expect(try context.fetch(FetchDescriptor<TimeSession>()).isEmpty)
        #expect(try context.fetch(FetchDescriptor<TimeSegment>()).isEmpty)

        store.hideAppleHealthFromTimeline()
        #expect(store.task(for: running.id) != nil)
        #expect(store.task(for: sleep.id) != nil)
    }

    @Test @MainActor
    func enabledRefreshRetriesAndConsumesOnlyConfirmedClearRecovery()
        async throws
    {
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
        source: String = "test",
        productType: String? = nil
    ) -> AppleHealthSleepSample {
        AppleHealthSleepSample(
            id: id,
            stage: stage,
            startedAt: Date(timeIntervalSince1970: start),
            endedAt: Date(timeIntervalSince1970: end),
            sourceBundleIdentifier: source,
            sourceProductType: productType
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
    var authorizationRequestStatusCount = 0
    var authorizationRequestCount = 0
    var sampleRequestIntervals: [DateInterval] = []
    var batch: AppleHealthSampleBatch
    var requestStatus: AppleHealthAuthorizationRequestStatus
    var authorizationRequestStatusError: Error?
    var authorizationError: Error?
    var sampleError: Error?
    var suspendedSampleRequestsRemaining: Int
    var suspendedSampleRequestIDs: Set<UUID> = []
    var sampleCancellationCount = 0

    init(
        isHealthDataAvailable: Bool = true,
        batch: AppleHealthSampleBatch,
        requestStatus: AppleHealthAuthorizationRequestStatus = .unnecessary,
        suspendsSamples: Bool = false
    ) {
        self.isHealthDataAvailable = isHealthDataAvailable
        self.batch = batch
        self.requestStatus = requestStatus
        suspendedSampleRequestsRemaining = suspendsSamples ? 1 : 0
    }

    func authorizationRequestStatus() async throws
        -> AppleHealthAuthorizationRequestStatus
    {
        authorizationRequestStatusCount += 1
        if let authorizationRequestStatusError {
            throw authorizationRequestStatusError
        }
        return requestStatus
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
        if suspendedSampleRequestsRemaining > 0 {
            suspendedSampleRequestsRemaining -= 1
            let requestID = UUID()
            suspendedSampleRequestIDs.insert(requestID)
            do {
                while suspendedSampleRequestIDs.contains(requestID) {
                    try Task.checkCancellation()
                    await Task.yield()
                }
            } catch {
                suspendedSampleRequestIDs.remove(requestID)
                sampleCancellationCount += 1
                throw error
            }
        }
        return batch
    }
}

@MainActor
private final class StubAppleHealthTimelinePreferences:
    AppleHealthTimelinePreferenceStoring
{
    var isTimelineEnabled: Bool
    var taskCatalogClearRecoveryTaskIDs: Set<UUID> = []

    init(isTimelineEnabled: Bool) {
        self.isTimelineEnabled = isTimelineEnabled
    }
}
