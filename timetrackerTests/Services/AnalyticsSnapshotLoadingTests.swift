import Foundation
import SwiftData
import Testing
@testable import timetracker

/// Pins the analytics snapshot a cache miss produces for a fixed ledger, and
/// that the loaded snapshot is then served from the store cache.
@Suite(.serialized)
@MainActor
struct AnalyticsSnapshotLoadingTests {
    private struct Fixture {
        let store: TimeTrackerStore
        let calendar: Calendar
        let writing: TaskNode
        let draft: TaskNode
        let reading: TaskNode
        let referenceDate: Date
    }

    private func makeFixture() throws -> Fixture {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "UTC"))
        calendar.locale = Locale(identifier: "en_US_POSIX")
        func date(_ day: Int, _ hour: Int, _ minute: Int = 0) throws -> Date {
            try #require(calendar.date(from: DateComponents(
                year: 2024, month: 3, day: day, hour: hour, minute: minute
            )))
        }

        let context = try makeTestContext()
        let store = makeTestStore()
        try store.configureIfNeeded(context: context)
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "seed")
        let category = try taskRepository.createCategory(title: "Work")
        let writing = try taskRepository.createTask(
            title: "Writing",
            parentID: nil,
            categoryID: category.id
        )
        let draft = try taskRepository.createTask(title: "Draft", parentID: writing.id)
        let reading = try taskRepository.createTask(title: "Reading", parentID: nil)
        let ledger = SwiftDataTimeTrackingRepository(context: context, deviceID: "seed")
        try ledger.addManualSegment(
            taskID: draft.id, startedAt: date(13, 9), endedAt: date(13, 10), note: nil
        )
        try ledger.addManualSegment(
            taskID: reading.id, startedAt: date(13, 9, 30), endedAt: date(13, 10, 30), note: nil
        )
        try ledger.addManualSegment(
            taskID: writing.id, startedAt: date(14, 14), endedAt: date(14, 14, 20), note: nil
        )
        // Previous week, for the comparison window.
        try ledger.addManualSegment(
            taskID: reading.id, startedAt: date(6, 9), endedAt: date(6, 9, 45), note: nil
        )
        try store.refresh()
        return try Fixture(
            store: store,
            calendar: calendar,
            writing: writing,
            draft: draft,
            reading: reading,
            referenceDate: date(13, 12)
        )
    }

    @Test
    func weekSnapshotAggregatesTheSeededLedgerAndIsCached() async throws {
        let fixture = try makeFixture()
        let evaluation = AnalyticsRange.week.evaluation(
            referenceDate: fixture.referenceDate,
            liveNow: Date(),
            calendar: fixture.calendar
        )
        #expect(fixture.store.cachedAnalyticsSnapshot(
            for: .week, evaluation: evaluation, calendar: fixture.calendar
        ) == nil)

        let snapshot = try #require(await fixture.store.loadAnalyticsSnapshot(
            for: .week, evaluation: evaluation, calendar: fixture.calendar
        ))

        #expect(snapshot.overview.grossSeconds == 8400)
        #expect(snapshot.overview.wallSeconds == 6600)
        #expect(snapshot.overview.overlapSeconds == 1800)
        #expect(snapshot.taskBreakdown.map(\.taskID) == [
            fixture.draft.id, fixture.reading.id, fixture.writing.id,
        ])
        #expect(snapshot.taskBreakdown.map(\.grossSeconds) == [3600, 3600, 1200])
        #expect(snapshot.rootBreakdown.map(\.title) == ["Writing", "Reading"])
        #expect(snapshot.rootBreakdown.map(\.grossSeconds) == [4800, 3600])
        #expect(snapshot.categoryBreakdown.map(\.title) == [
            "Work", AppStrings.localized("taskCategory.uncategorized"),
        ])
        #expect(snapshot.categoryBreakdown.map(\.grossSeconds) == [4800, 3600])
        #expect(snapshot.comparison.window.basis == .completePeriods)
        #expect(snapshot.comparison.currentGrossSeconds == 8400)
        #expect(snapshot.comparison.previousGrossSeconds == 2700)
        #expect(snapshot.daily.count == 7)
        #expect(snapshot.daily.map(\.grossSeconds).reduce(0, +) == 8400)
        #expect(snapshot.overlaps.map(\.excessDurationSeconds) == [1800])
        #expect(snapshot.rhythm.segmentCount == 3)
        #expect(snapshot.rhythm.peakHour == 9)
        #expect(snapshot.quality.switchCount == 2)
        #expect(snapshot.timeline.entries.isEmpty)

        let cached = try #require(fixture.store.cachedAnalyticsSnapshot(
            for: .week, evaluation: evaluation, calendar: fixture.calendar
        ))
        #expect(cached.overview.grossSeconds == snapshot.overview.grossSeconds)
        #expect(cached.taskBreakdown.map(\.taskID) == snapshot.taskBreakdown.map(\.taskID))
    }

    @Test
    func concurrentLoadsOfOnePeriodShareTheAggregation() async throws {
        let fixture = try makeFixture()
        let evaluation = AnalyticsRange.week.evaluation(
            referenceDate: fixture.referenceDate,
            liveNow: Date(),
            calendar: fixture.calendar
        )

        async let first = fixture.store.loadAnalyticsSnapshot(
            for: .week, evaluation: evaluation, calendar: fixture.calendar
        )
        async let second = fixture.store.loadAnalyticsSnapshot(
            for: .week, evaluation: evaluation, calendar: fixture.calendar
        )
        let snapshots = await [first, second]

        #expect(snapshots.map { $0?.overview.grossSeconds } == [8400, 8400])
        #expect(fixture.store.analyticsSnapshotLoads.isEmpty)
    }

    @Test
    func todaySnapshotIncludesTheVisualReadModels() async throws {
        let fixture = try makeFixture()
        let evaluation = AnalyticsRange.today.evaluation(
            referenceDate: fixture.referenceDate,
            liveNow: Date(),
            calendar: fixture.calendar
        )

        let snapshot = try #require(await fixture.store.loadAnalyticsSnapshot(
            for: .today, evaluation: evaluation, calendar: fixture.calendar
        ))

        #expect(snapshot.overview.grossSeconds == 7200)
        #expect(snapshot.overview.wallSeconds == 5400)
        #expect(snapshot.timeline.entries.map(\.durationSeconds).sorted() == [3600, 3600])
        #expect(snapshot.todayActivity.count == 24)
        #expect(snapshot.todayActivity[9].totalSeconds == 5400)
        #expect(snapshot.todayActivity[10].totalSeconds == 1800)
        #expect(snapshot.overlaps.map(\.excessDurationSeconds) == [1800])
        #expect(snapshot.overlaps.first?.visibleParticipants.map(\.title).sorted() == [
            "Draft", "Reading",
        ])
        #expect(fixture.store.cachedAnalyticsSnapshot(
            for: .today, evaluation: evaluation, calendar: fixture.calendar
        ) != nil)
    }
}
