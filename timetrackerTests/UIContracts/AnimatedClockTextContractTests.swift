import Foundation
import Testing

@Suite(.serialized)
struct AnimatedClockTextContractTests {
    @Test
    func runningClocksShareANativeNumericTransitionWithReduceMotionFallback() throws {
        let shared = try sourceText(
            "timetracker/SharedUI/Components/AnimatedClockText.swift"
        )
        let duration = try sourceText(
            "timetracker/SharedUI/Components/DurationLabels.swift"
        )
        let timerFace = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroTimerFace.swift"
        )
        let activeCountdown = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroActiveCountdownView.swift"
        )
        let setup = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroFocusSetupControls.swift"
        )

        #expect(shared.contains("struct AnimatedClockText: View"))
        #expect(shared.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(shared.contains(".numericText(value: Double(value))"))
        #expect(shared.contains("reduceMotion ? nil : .snappy(duration: 0.22)"))
        #expect(shared.contains(".monospacedDigit()"))
        #expect(shared.contains("TimelineView") == false)
        #expect(duration.contains("AnimatedClockText("))
        #expect(timerFace.contains("AnimatedClockText(text: timeText, value: timeValue)"))
        #expect(timerFace.contains("Text(timeText)") == false)
        #expect(activeCountdown.contains("timeValue: remaining"))
        #expect(setup.contains("timeValue: plan.focusSeconds"))
    }
}
