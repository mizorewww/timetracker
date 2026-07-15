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
