import Foundation
import Testing
@testable import timetracker

struct TaskRecurrenceDayKeyTests {
    @Test
    func dayKeyUsesTheRulesFixedTimeZoneForTheSameInstant() throws {
        let instant = try utcDate(
            year: 2026,
            month: 7,
            day: 20,
            hour: 16,
            minute: 30
        )
        let singapore = try #require(
            TimeZone(identifier: "Asia/Singapore")
        )
        let losAngeles = try #require(
            TimeZone(identifier: "America/Los_Angeles")
        )

        #expect(
            TaskRecurrenceDayKey.value(
                for: instant,
                timeZone: singapore
            ) == "2026-07-21"
        )
        #expect(
            TaskRecurrenceDayKey.value(
                for: instant,
                timeZone: losAngeles
            ) == "2026-07-20"
        )
    }

    @Test
    func dayKeyChangesAtSpringAndFallDSTMidnight() throws {
        let losAngeles = try #require(
            TimeZone(identifier: "America/Los_Angeles")
        )
        let springBefore = try utcDate(
            year: 2026,
            month: 3,
            day: 9,
            hour: 6,
            minute: 59,
            second: 59
        )
        let springAfter = try utcDate(
            year: 2026,
            month: 3,
            day: 9,
            hour: 7
        )
        let fallBefore = try utcDate(
            year: 2026,
            month: 11,
            day: 2,
            hour: 7,
            minute: 59,
            second: 59
        )
        let fallAfter = try utcDate(
            year: 2026,
            month: 11,
            day: 2,
            hour: 8
        )

        #expect(
            TaskRecurrenceDayKey.value(
                for: springBefore,
                timeZone: losAngeles
            ) == "2026-03-08"
        )
        #expect(
            TaskRecurrenceDayKey.value(
                for: springAfter,
                timeZone: losAngeles
            ) == "2026-03-09"
        )
        #expect(
            TaskRecurrenceDayKey.value(
                for: fallBefore,
                timeZone: losAngeles
            ) == "2026-11-01"
        )
        #expect(
            TaskRecurrenceDayKey.value(
                for: fallAfter,
                timeZone: losAngeles
            ) == "2026-11-02"
        )
    }

    private func utcDate(
        year: Int,
        month: Int,
        day: Int,
        hour: Int,
        minute: Int = 0,
        second: Int = 0
    ) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US_POSIX")
        calendar.timeZone = try #require(
            TimeZone(secondsFromGMT: 0)
        )
        return try #require(
            calendar.date(
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
