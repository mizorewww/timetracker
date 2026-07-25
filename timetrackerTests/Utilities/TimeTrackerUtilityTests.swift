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

        #expect(service.totalSeconds(segments: [first, second], mode: .gross) == 7200)
        #expect(service.totalSeconds(segments: [first, second], mode: .wallClock) == 5400)
    }

    @Test @MainActor
    func trackedTimeAggregationClipsFutureEndsAndIgnoresFutureStarts() {
        let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
        let taskID = UUID()
        let spanningNow = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now.addingTimeInterval(3600)
        )
        let activeOverlap = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: now.addingTimeInterval(-1800)
        )
        let futureOnly = TimeSegment(
            sessionID: UUID(),
            taskID: taskID,
            source: .timer,
            deviceID: "test",
            startedAt: now,
            endedAt: now.addingTimeInterval(7200)
        )
        let service = TimeAggregationService()

        #expect(service.grossSeconds([spanningNow, activeOverlap, futureOnly], now: now) == 5400)
        #expect(service.wallClockSeconds([spanningNow, activeOverlap, futureOnly], now: now) == 3600)
        #expect(TrackedTimePolicy.elapsedSeconds(
            startedAt: now,
            endedAt: nil,
            now: now
        ) == 0)
    }

    @Test @MainActor
    func trackedTimeClippingUsesElapsedSecondsAcrossDSTSpringForward() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "America/Los_Angeles"))
        let start = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 0
        )))
        let now = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 4
        )))
        let dirtyFutureEnd = try #require(calendar.date(from: DateComponents(
            year: 2026,
            month: 3,
            day: 8,
            hour: 5
        )))
        let segment = TimeSegment(
            sessionID: UUID(),
            taskID: UUID(),
            source: .timer,
            deviceID: "test",
            startedAt: start,
            endedAt: dirtyFutureEnd
        )
        let service = TimeAggregationService()
        let interval = try #require(TrackedTimePolicy.interval(
            startedAt: segment.startedAt,
            endedAt: segment.endedAt,
            now: now
        ))

        #expect(interval.end == now)
        #expect(service.grossSeconds([segment], now: now) == 3 * 3600)
        #expect(service.secondsByDay(intervals: [interval], calendar: calendar) == [start: 3 * 3600])
    }

    @Test
    func durationFormattingUsesLocalizedCompactTextAndStableTimerClock() {
        let seconds = 4 * 3600 + 35 * 60
        #expect(DurationFormatter.compact(seconds, locale: Locale(identifier: "en_US")) == "4 hr, 35 min")
        #expect(DurationFormatter.compact(seconds, locale: Locale(identifier: "zh_Hans")) == "4小时35分钟")
        #expect(DurationFormatter.compact(seconds, locale: Locale(identifier: "zh_Hant")) == "4小時35分鐘")
        #expect(DurationFormatter.compact(40, locale: Locale(identifier: "en_US")) == "0 min")
        #expect(DurationFormatter.chart(0, locale: Locale(identifier: "en_US")) == "0 sec")
        #expect(DurationFormatter.chart(40, locale: Locale(identifier: "en_US")) == "40 sec")
        #expect(DurationFormatter.chart(65, locale: Locale(identifier: "en_US")) == "1 min")
        #expect(DurationFormatter.chartAxis(90, locale: Locale(identifier: "en_US")) == "1 min, 30 sec")
        #expect(DurationFormatter.chartAxis(150, locale: Locale(identifier: "en_US")) == "2 min, 30 sec")
        #expect(DurationFormatter.clock(84) == "01:24")
        #expect(
            DurationFormatter.spoken(65, locale: Locale(identifier: "en_US")) ==
                "1 minute, 5 seconds"
        )
    }

    @Test @MainActor
    func trackedTimeDisplaySnapshotClipsFutureValuesAndZeroesFutureOnlyRows() {
        let now = Date(timeIntervalSinceReferenceDate: 2_000_000)
        let clipped = TrackedTimeDisplaySnapshot(
            startedAt: now.addingTimeInterval(-3600),
            endedAt: now.addingTimeInterval(3600),
            now: now
        )
        let futureOnly = TrackedTimeDisplaySnapshot(
            startedAt: now.addingTimeInterval(600),
            endedAt: now.addingTimeInterval(7200),
            now: now
        )
        let futureActive = TrackedTimeDisplaySnapshot(
            startedAt: now.addingTimeInterval(600),
            endedAt: nil,
            now: now
        )
        let completedEnd = now.addingTimeInterval(-900)
        let completed = TrackedTimeDisplaySnapshot(
            startedAt: now.addingTimeInterval(-1800),
            endedAt: completedEnd,
            now: now
        )

        #expect(clipped.end == now)
        #expect(clipped.elapsedSeconds == 3600)
        #expect(clipped.usesCurrentEndLabel)
        #expect(futureOnly.start == now)
        #expect(futureOnly.end == now)
        #expect(futureOnly.elapsedSeconds == 0)
        #expect(futureOnly.usesCurrentEndLabel)
        #expect(futureActive.start == now)
        #expect(futureActive.end == now)
        #expect(futureActive.elapsedSeconds == 0)
        #expect(futureActive.usesCurrentEndLabel)
        #expect(completed.end == completedEnd)
        #expect(completed.elapsedSeconds == 900)
        #expect(completed.usesCurrentEndLabel == false)
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
    func customTaskColorsMeetSmallTextContrastTargetsInBothAppearances() {
        let bright = AccessibleSRGB(red: 1, green: 0.84, blue: 0.04)
            .adapted(forDarkBackground: false)
        let dark = AccessibleSRGB(red: 0.02, green: 0.04, blue: 0.08)
            .adapted(forDarkBackground: true)

        #expect(bright.relativeLuminance <= 0.184)
        #expect(dark.relativeLuminance >= 0.174)
        #expect(bright.prefersDarkForeground)
        #expect(dark.prefersDarkForeground == false)
        #expect(bright.contrastRatio(againstLuminance: 0) >= 4.5)
        #expect(dark.contrastRatio(againstLuminance: 1) >= 4.5)

        let darkModePastel = AccessibleSRGB(red: 0.99, green: 0.99, blue: 0.80)
            .adapted(forDarkBackground: true)
        #expect(darkModePastel.prefersDarkForeground)
        #expect(darkModePastel.contrastRatio(againstLuminance: 0) >= 4.5)
    }

    @Test
    func taskColorHexRoundTripsSystemPickerValuesCanonically() {
        #expect(TaskColorPalette.normalizedHex("#0a84ff") == "0A84FF")
        #expect(TaskColorPalette.normalizedHex("12Ab34") == "12AB34")
        #expect(TaskColorPalette.normalizedHex("#aB3") == "AABB33")
        #expect(TaskColorPalette.normalizedHex("12345") == nil)
        #expect(TaskColorPalette.normalizedHex("GGGGGG") == nil)
        #expect(TaskColorPalette.hex(red: 0, green: 0.5, blue: 1) == "0080FF")
        #expect(ChecklistVisualSanitizer.sanitizedColor("#12ab34") == "12AB34")
    }

    @Test
    func blossomTouchScaleMakesUpstreamPetalsFingerSized() {
        let metrics = SymbolBlossomTouchMetrics.self

        #expect(metrics.scale > 1)
        #expect(
            abs(metrics.scaled(metrics.sourcePetalDiameter) - metrics.targetDiameter) <
                0.001
        )
    }

    @Test @MainActor
    func countdownEventsAreSwiftDataBackedAndAllowEmptyList() throws {
        let context = try makeTestContext()
        let store = makeTestStore()
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
