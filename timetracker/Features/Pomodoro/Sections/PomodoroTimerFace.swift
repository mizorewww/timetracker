import SwiftUI

struct PomodoroTimerFace: View {
    let timeText: String
    let timeValue: Int
    let title: String
    let subtitle: String?
    let titleColor: Color
    let spokenLabel: String?
    let spokenValue: String?

    init(
        timeText: String,
        timeValue: Int,
        title: String,
        subtitle: String? = nil,
        titleColor: Color,
        spokenLabel: String? = nil,
        spokenValue: String? = nil
    ) {
        self.timeText = timeText
        self.timeValue = timeValue
        self.title = title
        self.subtitle = subtitle
        self.titleColor = titleColor
        self.spokenLabel = spokenLabel
        self.spokenValue = spokenValue
    }

    var body: some View {
        VStack(spacing: 10) {
            AnimatedClockText(text: timeText, value: timeValue)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .foregroundStyle(PomodoroStyle.timerText)

            Text(title)
                .font(.title2.bold())
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundStyle(titleColor)

            if let subtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spokenLabel ?? title)
        .accessibilityValue(spokenValue ?? timeText)
        .accessibilityIdentifier("pomodoro.timerFace")
    }
}
