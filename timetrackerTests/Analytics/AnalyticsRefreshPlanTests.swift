import Foundation
import Testing

@testable import timetracker

struct AnalyticsRefreshPlanTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    @Test
    func activeCurrentPeriodUsesTheNextAbsoluteMinuteBucket() throws {
        let liveNow = Date(timeIntervalSinceReferenceDate: 42 * 60 + 59.9)
        let plan = try #require(
            AnalyticsRefreshPlan.next(
                liveNow: liveNow,
                followsCurrentPeriod: true,
                liveRefreshBucket: 42,
                calendar: calendar
            )
        )

        #expect(plan.reason == .liveMinute)
        #expect(plan.deadline == Date(timeIntervalSinceReferenceDate: 43 * 60))
    }

    @Test
    func staleLiveBucketStillMovesToAFutureBoundary() throws {
        let liveNow = Date(timeIntervalSinceReferenceDate: 43 * 60 + 10)
        let plan = try #require(
            AnalyticsRefreshPlan.next(
                liveNow: liveNow,
                followsCurrentPeriod: true,
                liveRefreshBucket: 42,
                calendar: calendar
            )
        )

        #expect(plan.reason == .liveMinute)
        #expect(plan.deadline == Date(timeIntervalSinceReferenceDate: 44 * 60))
    }

    @Test
    func historicalPeriodDoesNotScheduleAClockTask() throws {
        let liveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))
        )
        let plan = AnalyticsRefreshPlan.next(
            liveNow: liveNow,
            followsCurrentPeriod: false,
            liveRefreshBucket: 123,
            calendar: calendar
        )

        #expect(plan == nil)
    }

    @Test
    func aNewClockSampleChangesThePlanIdentityWithinOneBucket() throws {
        let firstSample = Date(timeIntervalSinceReferenceDate: 42 * 60 + 10)
        let secondSample = Date(timeIntervalSinceReferenceDate: 42 * 60 + 20)
        let first = try #require(
            AnalyticsRefreshPlan.next(
                liveNow: firstSample,
                followsCurrentPeriod: true,
                liveRefreshBucket: 42,
                calendar: calendar
            )
        )
        let second = try #require(
            AnalyticsRefreshPlan.next(
                liveNow: secondSample,
                followsCurrentPeriod: true,
                liveRefreshBucket: 42,
                calendar: calendar
            )
        )

        #expect(first.deadline == second.deadline)
        #expect(first != second)
    }

    @Test
    func idleRefreshUsesCalendarMidnightAcrossDaylightSaving() throws {
        var losAngeles = calendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let liveNow = try #require(
            losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 0, minute: 30))
        )
        let plan = try #require(
            AnalyticsRefreshPlan.next(
                liveNow: liveNow,
                followsCurrentPeriod: true,
                liveRefreshBucket: nil,
                calendar: losAngeles
            )
        )

        #expect(plan.reason == .nextLocalDay)
        #expect(
            losAngeles.dateComponents([.year, .month, .day, .hour], from: plan.deadline) ==
                DateComponents(year: 2026, month: 3, day: 9, hour: 0)
        )
        #expect(plan.deadline.timeIntervalSince(liveNow) == 22.5 * 60 * 60)
    }

    @Test
    func idleCurrentWeekRequestChangesAcrossLocalMidnight() throws {
        let firstDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 23, minute: 59))
        )
        let nextDay = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 0, minute: 1))
        )
        let firstEvaluation = AnalyticsRange.week.evaluation(
            referenceDate: firstDay,
            liveNow: firstDay,
            calendar: calendar
        )
        let nextEvaluation = AnalyticsRange.week.evaluation(
            referenceDate: nextDay,
            liveNow: nextDay,
            calendar: calendar
        )
        #expect(firstEvaluation.interval == nextEvaluation.interval)

        let firstRequest = AnalyticsSnapshotRequest(
            range: .week,
            evaluation: firstEvaluation,
            revision: 1,
            liveRefreshBucket: nil,
            calendar: calendar
        )
        let nextRequest = AnalyticsSnapshotRequest(
            range: .week,
            evaluation: nextEvaluation,
            revision: 1,
            liveRefreshBucket: nil,
            calendar: calendar
        )

        #expect(firstRequest != nextRequest)
        #expect(firstRequest.evaluationKey.liveDayStart == calendar.startOfDay(for: firstDay))
        #expect(nextRequest.evaluationKey.liveDayStart == calendar.startOfDay(for: nextDay))
    }

    @Test
    func completedPeriodRequestDoesNotChangeWithLaterWallClockDays() throws {
        let selected = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 7, hour: 12))
        )
        let firstLiveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 12))
        )
        let nextLiveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 12))
        )
        let first = AnalyticsSnapshotRequest(
            range: .week,
            evaluation: AnalyticsRange.week.evaluation(
                referenceDate: selected,
                liveNow: firstLiveNow,
                calendar: calendar
            ),
            revision: 1,
            liveRefreshBucket: nil,
            calendar: calendar
        )
        let second = AnalyticsSnapshotRequest(
            range: .week,
            evaluation: AnalyticsRange.week.evaluation(
                referenceDate: selected,
                liveNow: nextLiveNow,
                calendar: calendar
            ),
            revision: 1,
            liveRefreshBucket: nil,
            calendar: calendar
        )

        #expect(first == second)
        #expect(first.evaluationKey.liveDayStart == nil)
    }
}
