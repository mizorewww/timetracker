import SwiftUI

struct PomodoroTimerFace: View {
    let timeText: String
    let title: String
    let titleColor: Color

    var body: some View {
        VStack(spacing: 10) {
            Text(timeText)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .foregroundStyle(PomodoroStyle.timerText)

            Text(title)
                .font(.title2.bold())
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(titleColor)
        }
        .frame(maxWidth: .infinity, minHeight: 132)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityValue(timeText)
        .accessibilityIdentifier("pomodoro.timerFace")
    }
}
