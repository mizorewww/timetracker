import Foundation
import Testing
@testable import timetracker

struct PomodoroPresentationTests {
    @Test
    func builtInPlansKeepStableUniqueSelectionIdentity() {
        let firstRead = PomodoroPlan.defaultPlans
        let secondRead = PomodoroPlan.defaultPlans

        #expect(firstRead.map(\.id) == secondRead.map(\.id))
        #expect(Set(firstRead.map(\.id)).count == firstRead.count)
    }

    @Test
    func countdownScheduleStopsAtDeadlineAndIncludesFractionalEnd() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)
        let deadline = start.addingTimeInterval(2.5)

        let entries = Array(
            PomodoroCountdownSchedule.entries(
                from: start,
                through: deadline,
                interval: 1
            )
        )

        #expect(entries == [
            start,
            start.addingTimeInterval(1),
            start.addingTimeInterval(2),
            deadline
        ])
    }

    @Test
    func countdownScheduleDoesNotPollWithoutAFutureDeadline() {
        let start = Date(timeIntervalSinceReferenceDate: 1_000)

        #expect(Array(PomodoroCountdownSchedule.entries(from: start, through: nil)) == [start])
        #expect(
            Array(
                PomodoroCountdownSchedule.entries(
                    from: start,
                    through: start.addingTimeInterval(-10)
                )
            ) == [start]
        )
    }

    @Test
    func breakActionAllowsEarlySkipAndChangesCopyWhenReady() {
        let early = PomodoroBreakActionPresentation(remainingSeconds: 30)
        let ready = PomodoroBreakActionPresentation(remainingSeconds: 0)

        #expect(early.titleKey == "pomodoro.skipBreak")
        #expect(early.systemImage == "forward.fill")
        #expect(ready.titleKey == "pomodoro.startNextFocus")
        #expect(ready.systemImage == "play.circle.fill")
    }

    @Test
    func pageLayoutUsesFiniteViewportWidthAndReflowsForAccessibilityText() {
        let phone = PomodoroPageLayoutPolicy(
            viewportWidth: 402,
            prefersSingleColumn: false
        )
        let wide = PomodoroPageLayoutPolicy(
            viewportWidth: 1_024,
            prefersSingleColumn: false
        )
        let accessibility = PomodoroPageLayoutPolicy(
            viewportWidth: 1_024,
            prefersSingleColumn: true
        )

        #expect(phone.contentWidth == 366)
        #expect(phone.usesTwoColumnContent == false)
        #expect(wide.contentWidth == AppLayout.desktopReadableWidth)
        #expect(wide.usesTwoColumnContent)
        #expect(accessibility.usesTwoColumnContent == false)
    }
}
