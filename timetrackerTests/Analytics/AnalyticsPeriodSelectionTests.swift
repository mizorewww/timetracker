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
    func previousNavigationMovesByTheSelectedCalendarPeriod() throws {
        let liveNow = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)))

        let expectations: [(AnalyticsRange, DateComponents)] = [
            (.today, DateComponents(year: 2026, month: 7, day: 15, hour: 12)),
            (.week, DateComponents(year: 2026, month: 7, day: 9, hour: 12)),
            (.month, DateComponents(year: 2026, month: 6, day: 16, hour: 12))
        ]

        for (range, expectedComponents) in expectations {
            let expected = try #require(calendar.date(from: expectedComponents))
            #expect(
                AnalyticsPeriodNavigation.date(
                    byMoving: -1,
                    range: range,
                    referenceDate: liveNow,
                    liveNow: liveNow,
                    calendar: calendar
                ) == expected
            )
        }
    }

    @Test
    func nextNavigationNeverMovesBeyondToday() throws {
        let liveNow = try #require(calendar.date(from: DateComponents(year: 2026, month: 7, day: 16, hour: 12)))

        for range in AnalyticsRange.allCases {
            #expect(
                AnalyticsPeriodNavigation.date(
                    byMoving: 1,
                    range: range,
                    referenceDate: liveNow,
                    liveNow: liveNow,
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
            )
        ]

        for (range, referenceComponents, expectedComponents) in expectations {
            let referenceDate = try #require(calendar.date(from: referenceComponents))
            let expected = try #require(calendar.date(from: expectedComponents))
            #expect(
                AnalyticsPeriodNavigation.date(
                    byMoving: 1,
                    range: range,
                    referenceDate: referenceDate,
                    liveNow: liveNow,
                    calendar: calendar
                ) == expected
            )
        }
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
        let january = AnalyticsPeriodNavigation.date(
            byMoving: 1,
            range: .month,
            referenceDate: december,
            liveNow: liveNow,
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
            calendar: losAngeles
        )
        #expect(
            losAngeles.dateComponents([.year, .month, .day, .hour], from: afterDST) ==
                DateComponents(year: 2026, month: 3, day: 8, hour: 12)
        )
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
}
