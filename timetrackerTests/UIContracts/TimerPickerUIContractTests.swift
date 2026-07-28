import Foundation
import Testing
@testable import timetracker

struct TimerPickerUIContractTests {
    @Test
    func todayPrimaryTimerModesShareTheStartAnotherVisualGrammar() {
        #expect(
            TimerPickerMode.start.primaryActionSystemImage ==
                TimerPickerMode.startAnother.primaryActionSystemImage
        )
        #expect(TimerPickerMode.start.primaryActionSystemImage == "plus.circle")
        #expect(
            TimerPickerMode.switchTimer.primaryActionSystemImage ==
                "arrow.left.arrow.right.circle"
        )
    }

    @Test
    func pickerIndicatorsShareSystemCircleEnvelopesAndStableSlots() {
        #expect(
            TaskTimerActionKind.allCases.map(\.compactSystemImage) == [
                "play.circle.fill",
                "arrow.left.arrow.right.circle.fill",
                "checkmark.circle.fill",
                "stop.circle.fill",
            ]
        )
        #expect(
            TaskTimerActionKind.allCases.allSatisfy {
                $0.compactSystemImage.hasSuffix(".circle.fill")
            }
        )
        #expect(
            TaskPickerPassiveStatus.allCases.map(\.systemImage) == [
                "timer.circle.fill",
                "checkmark.circle.fill",
            ]
        )
        #expect(
            TaskPickerPassiveStatus.activeStates(
                isRunning: true,
                isSelected: true
            ) == [.running, .selected]
        )
        #expect(
            TaskPickerPassiveStatus.activeStates(
                isRunning: false,
                isSelected: false
            ).isEmpty
        )

        #if os(iOS)
        #expect(TaskPickerIndicatorMetrics.actionControlDimension == 54)
        #expect(TaskPickerIndicatorMetrics.passiveSlotDimension == 20)
        #else
        #expect(TaskPickerIndicatorMetrics.actionControlDimension == 28)
        #expect(TaskPickerIndicatorMetrics.passiveSlotDimension == 16)
        #endif
    }
}
