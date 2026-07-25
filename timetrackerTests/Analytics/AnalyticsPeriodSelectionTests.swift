import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct AnalyticsPeriodSelectionTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        calendar.firstWeekday = 2
        return calendar
    }

    @Test
    func evaluationSeparatesSelectedPeriodCutoffAndWallClock() throws {
        let liveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))
        )
        let historicalReference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 9))
        )
        let futureReference = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 18, hour: 9))
        )

        let current = AnalyticsRange.today.evaluation(
            referenceDate: liveNow,
            liveNow: liveNow,
            calendar: calendar
        )
        let historical = AnalyticsRange.today.evaluation(
            referenceDate: historicalReference,
            liveNow: liveNow,
            calendar: calendar
        )
        let future = AnalyticsRange.today.evaluation(
            referenceDate: futureReference,
            liveNow: liveNow,
            calendar: calendar
        )

        #expect(current.cutoff == liveNow)
        #expect(current.clockReference == liveNow)
        #expect(historical.cutoff == historical.interval.end)
        #expect(historical.clockReference == liveNow)
        #expect(future.cutoff == future.interval.start)
        #expect(future.clockReference == liveNow)
    }

    @Test
    func historicalEvaluationUsesExactCalendarBoundariesAcrossDST() throws {
        var losAngeles = calendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let liveNow = try #require(
            losAngeles.date(from: DateComponents(year: 2026, month: 11, day: 10, hour: 12))
        )
        let springReference = try #require(
            losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 8, hour: 12))
        )
        let fallReference = try #require(
            losAngeles.date(from: DateComponents(year: 2026, month: 11, day: 1, hour: 12))
        )

        let spring = AnalyticsRange.today.evaluation(
            referenceDate: springReference,
            liveNow: liveNow,
            calendar: losAngeles
        )
        let fall = AnalyticsRange.today.evaluation(
            referenceDate: fallReference,
            liveNow: liveNow,
            calendar: losAngeles
        )

        #expect(spring.interval.duration == 23 * 3600)
        #expect(fall.interval.duration == 25 * 3600)
        #expect(spring.cutoff == spring.interval.end)
        #expect(fall.cutoff == fall.interval.end)
    }

    @Test
    func previousNavigationMovesByTheSelectedCalendarPeriod() throws {
        let liveNow = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)))

        let expectations: [(AnalyticsRange, DateComponents)] = [
            (.today, DateComponents(year: 2026, month: 7, day: 15, hour: 12)),
            (.week, DateComponents(year: 2026, month: 7, day: 9, hour: 12)),
            (.month, DateComponents(year: 2026, month: 6, day: 16, hour: 12)),
        ]

        for (range, expectedComponents) in expectations {
            let expected = try #require(calendar.date(from: expectedComponents))
            var monthAnchor: AnalyticsMonthNavigationAnchor?
            #expect(
                AnalyticsPeriodNavigation.date(
                    byMoving: -1,
                    range: range,
                    referenceDate: liveNow,
                    liveNow: liveNow,
                    monthAnchor: &monthAnchor,
                    calendar: calendar
                ) == expected
            )
        }
    }

    @Test
    func nextNavigationNeverMovesBeyondToday() throws {
        let liveNow = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)))

        for range in AnalyticsRange.allCases {
            var monthAnchor: AnalyticsMonthNavigationAnchor?
            #expect(
                AnalyticsPeriodNavigation.date(
                    byMoving: 1,
                    range: range,
                    referenceDate: liveNow,
                    liveNow: liveNow,
                    monthAnchor: &monthAnchor,
                    calendar: calendar
                ) == liveNow
            )
        }
    }

    @Test
    func nextNavigationMovesHistoricalPeriodsForward() throws {
        let liveNow = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12))
        )
        let expectations: [(AnalyticsRange, DateComponents, DateComponents)] = [
            (
                .today,
                DateComponents(year: 2026, month: 7, day: 14, hour: 12),
                DateComponents(year: 2026, month: 7, day: 15, hour: 12)
            ),
            (
                .week,
                DateComponents(year: 2026, month: 7, day: 2, hour: 12),
                DateComponents(year: 2026, month: 7, day: 9, hour: 12)
            ),
            (
                .month,
                DateComponents(year: 2026, month: 5, day: 16, hour: 12),
                DateComponents(year: 2026, month: 6, day: 16, hour: 12)
            ),
        ]

        for (range, referenceComponents, expectedComponents) in expectations {
            let referenceDate = try #require(calendar.date(from: referenceComponents))
            let expected = try #require(calendar.date(from: expectedComponents))
            var monthAnchor: AnalyticsMonthNavigationAnchor?
            #expect(
                AnalyticsPeriodNavigation.date(
                    byMoving: 1,
                    range: range,
                    referenceDate: referenceDate,
                    liveNow: liveNow,
                    monthAnchor: &monthAnchor,
                    calendar: calendar
                ) == expected
            )
        }
    }

    @Test
    func monthPeriodArithmeticMovesFromTheSelectedCalendarIntervalStart() throws {
        let january = try makeDate(2025, 1, 31, hour: 14)
        let destination = try #require(
            AnalyticsRange.month.date(byAdding: 1, to: january, calendar: calendar)
        )
        let expected = try makeDate(2025, 2, 1)

        #expect(destination == expected)
    }

    @Test
    func navigationUsesCalendarAcrossYearAndDaylightSavingBoundaries() throws {
        var losAngeles = calendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let liveNow = try #require(
            losAngeles.date(from: DateComponents(year: 2027, month: 2, day: 1, hour: 12))
        )

        let december = try #require(
            losAngeles.date(from: DateComponents(year: 2026, month: 12, day: 15, hour: 12))
        )
        var monthAnchor: AnalyticsMonthNavigationAnchor?
        let january = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: december,
            liveNow: liveNow,
            monthAnchor: &monthAnchor,
            calendar: losAngeles
        )
        #expect(
            losAngeles.dateComponents([.year, .month, .day, .hour], from: january) ==
                DateComponents(year: 2027, month: 1, day: 15, hour: 12)
        )

        let beforeDST = try #require(
            losAngeles.date(from: DateComponents(year: 2026, month: 3, day: 7, hour: 12))
        )
        let afterDST = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .today,
            referenceDate: beforeDST,
            liveNow: liveNow,
            monthAnchor: &monthAnchor,
            calendar: losAngeles
        )
        #expect(
            losAngeles.dateComponents([.year, .month, .day, .hour], from: afterDST) ==
                DateComponents(year: 2026, month: 3, day: 8, hour: 12)
        )
    }

    @Test
    func monthNavigationRetainsEndOfMonthAnchorAcrossShortMonths() throws {
        let liveNow = try makeDate(2025, 12, 15, hour: 12)
        let january = try makeDate(2025, 1, 31, hour: 14, minute: 37, second: 42)
        var anchor: AnalyticsMonthNavigationAnchor?

        let february = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: january,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )
        let march = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: february,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )
        let expectedFebruary = try makeDate(
            2025, 2, 28, hour: 14, minute: 37, second: 42
        )
        let expectedMarch = try makeDate(
            2025, 3, 31, hour: 14, minute: 37, second: 42
        )

        #expect(february == expectedFebruary)
        #expect(march == expectedMarch)
        #expect(anchor?.day == 31)
    }

    @Test
    func monthNavigationUsesLeapDayWithoutLosingTheOriginalAnchor() throws {
        let liveNow = try makeDate(2024, 12, 15, hour: 12)
        let january = try makeDate(2024, 1, 31, hour: 9)
        var anchor: AnalyticsMonthNavigationAnchor?

        let february = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: january,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )
        let march = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: february,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )
        let expectedFebruary = try makeDate(2024, 2, 29, hour: 9)
        let expectedMarch = try makeDate(2024, 3, 31, hour: 9)

        #expect(february == expectedFebruary)
        #expect(march == expectedMarch)
    }

    @Test
    func monthNavigationRetainsEndOfMonthAnchorWhenMovingBackward() throws {
        let liveNow = try makeDate(2025, 12, 15, hour: 12)
        let march = try makeDate(2025, 3, 31, hour: 8, minute: 15)
        var anchor: AnalyticsMonthNavigationAnchor?

        let february = AnalyticsPeriodNavigation.date(
            byMoving: -1,
            range: .month,
            referenceDate: march,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )
        let january = AnalyticsPeriodNavigation.date(
            byMoving: -1,
            range: .month,
            referenceDate: february,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )
        let expectedFebruary = try makeDate(2025, 2, 28, hour: 8, minute: 15)
        let expectedJanuary = try makeDate(2025, 1, 31, hour: 8, minute: 15)

        #expect(february == expectedFebruary)
        #expect(january == expectedJanuary)
    }

    @Test
    func monthNavigationPreservesLocalTimeAcrossDSTOffsetChanges() throws {
        var losAngeles = calendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let liveNow = try makeDate(2024, 12, 15, hour: 12, calendar: losAngeles)
        let january = try makeDate(
            2024, 1, 31, hour: 1, minute: 45, second: 27, calendar: losAngeles
        )
        var anchor: AnalyticsMonthNavigationAnchor?

        let february = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: january,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: losAngeles
        )
        let march = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: february,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: losAngeles
        )
        let expectedMarch = try makeDate(
            2024, 3, 31, hour: 1, minute: 45, second: 27, calendar: losAngeles
        )

        #expect(march == expectedMarch)
        #expect(losAngeles.timeZone.secondsFromGMT(for: february) == -8 * 3600)
        #expect(losAngeles.timeZone.secondsFromGMT(for: march) == -7 * 3600)
    }

    @Test
    func monthNavigationReturnsLiveNowAndClearsAnchorOnEnteringCurrentMonth() throws {
        let liveNow = try makeDate(2025, 3, 15, hour: 16, minute: 20, second: 30)
        let january = try makeDate(2025, 1, 31, hour: 9)
        var anchor: AnalyticsMonthNavigationAnchor?

        let february = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: january,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )
        let current = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: february,
            liveNow: liveNow,
            monthAnchor: &anchor,
            calendar: calendar
        )

        #expect(current == liveNow)
        #expect(anchor == nil)
    }

    @Test
    func monthLabelUsesTheInjectedCalendarTimeZone() throws {
        var losAngeles = calendar
        losAngeles.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let utc = try #require(TimeZone(secondsFromGMT: 0))
        var utcCalendar = calendar
        utcCalendar.timeZone = utc
        let instant = try #require(
            utcCalendar.date(
                from: DateComponents(year: 2027, month: 1, day: 1, hour: 0, minute: 30)
            )
        )

        #expect(
            AnalyticsPeriodText.title(
                for: .month,
                date: instant,
                liveNow: instant,
                calendar: losAngeles
            ) == "December 2026"
        )
    }

    @Test
    func todayAndYesterdayLabelsUseTheInjectedCurrentDate() throws {
        let liveNow = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 23)))
        let yesterday = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 15, hour: 1)))

        #expect(
            AnalyticsPeriodText.title(
                for: .today,
                date: liveNow,
                liveNow: liveNow,
                calendar: calendar
            ) == AppStrings.localized("analytics.period.today")
        )
        #expect(
            AnalyticsPeriodText.title(
                for: .today,
                date: yesterday,
                liveNow: liveNow,
                calendar: calendar
            ) == AppStrings.localized("analytics.period.yesterday")
        )
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        hour: Int = 0,
        minute: Int = 0,
        second: Int = 0,
        calendar requestedCalendar: Calendar? = nil
    ) throws -> Date {
        let selectedCalendar = requestedCalendar ?? calendar
        return try #require(
            selectedCalendar.date(
                from: DateComponents(
                    year: year,
                    month: month,
                    day: day,
                    hour: hour,
                    minute: minute,
                    second: second
                )
            )
        )
    }
}
