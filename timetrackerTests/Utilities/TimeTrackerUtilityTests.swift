import Foundation
import SwiftData
import SwiftUI
import Testing
@testable import timetracker

@Suite(.serialized)
struct TimeTrackerUtilityTests {
    @Test @MainActor
    func grossAndWallClockAggregationHandleOverlaps() {
        let taskID = UUID()
        let sessionA = UUID()
        let sessionB = UUID()
        let start = Date(timeIntervalSince1970: 1000)

        let first = TimeSegment(
            sessionID: sessionA,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: start.addingTimeInterval(60 * 60)
        )

        let second = TimeSegment(
            sessionID: sessionB,
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: start.addingTimeInterval(30 * 60),
            endedAt: start.addingTimeInterval(90 * 60)
        )

        let service = TimeAggregationService()

        #expect(service.totalSeconds(segments: [first, second], mode: .gross) == 7_200)
        #expect(service.totalSeconds(segments: [first, second], mode: .wallClock) == 5_400)
    }

    @Test
    func durationFormattingUsesLocalizedCompactTextAndStableTimerClock() {
        let seconds = 4 * 3600 + 35 * 60
        #expect(DurationFormatter.compact(seconds, locale: Locale(identifier: "en_US")) == "4 hr, 35 min")
        #expect(DurationFormatter.compact(seconds, locale: Locale(identifier: "zh_Hans")) == "4小时35分钟")
        #expect(DurationFormatter.compact(seconds, locale: Locale(identifier: "zh_Hant")) == "4小時35分鐘")
        #expect(DurationFormatter.compact(40, locale: Locale(identifier: "en_US")) == "0 min")
        #expect(DurationFormatter.clock(84) == "01:24")
    }

    @Test
    func dateFormattingRespectsLocaleDateOrderAndHourCycle() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(secondsFromGMT: 0))
        let date = try #require(
            calendar.date(from: DateComponents(year: 2026, month: 7, day: 14, hour: 13, minute: 5))
        )

        let usTime = TimeDisplayFormatter.hourMinute(
            date,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let britishTime = TimeDisplayFormatter.hourMinute(
            date,
            calendar: calendar,
            locale: Locale(identifier: "en_GB")
        )
        let usDateTime = TimeDisplayFormatter.monthDayHourMinute(
            date,
            calendar: calendar,
            locale: Locale(identifier: "en_US")
        )
        let chineseDateTime = TimeDisplayFormatter.monthDayHourMinute(
            date,
            calendar: calendar,
            locale: Locale(identifier: "zh_Hans")
        )

        #expect(usTime.contains("PM"))
        #expect(britishTime.contains("13:05"))
        #expect(usDateTime.contains("Jul 14"))
        #expect(chineseDateTime.contains("7月14日"))
        #expect(chineseDateTime.contains("13:05"))
    }

    @Test
    func customTaskColorsMeetNonTextContrastTargetsInBothAppearances() {
        let bright = AccessibleSRGB(red: 1, green: 0.84, blue: 0.04)
            .adapted(forDarkBackground: false)
        let dark = AccessibleSRGB(red: 0.02, green: 0.04, blue: 0.08)
            .adapted(forDarkBackground: true)

        #expect(bright.relativeLuminance <= 0.301)
        #expect(dark.relativeLuminance >= 0.099)
    }

    @Test @MainActor
    func countdownEventsAreSwiftDataBackedAndAllowEmptyList() throws {
        let context = try makeTestContext()
        let store = TimeTrackerStore()
        store.configureIfNeeded(context: context)

        #expect(store.countdownEvents.isEmpty)

        store.addCountdownEvent()
        #expect(store.countdownEvents.count == 1)

        let event = try #require(store.countdownEvents.first)
        store.updateCountdownEvent(event, title: "Launch", date: Date(timeIntervalSince1970: 200))
        #expect(store.countdownEvents.first?.title == "Launch")

        store.deleteCountdownEvent(event)
        #expect(store.countdownEvents.isEmpty)
    }
}
