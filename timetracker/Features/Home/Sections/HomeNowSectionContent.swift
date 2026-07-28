import SwiftUI

/// Shared Now content used by every platform: iPhone hosts it in a grouped
/// list section, iPad and macOS in an app card, so the Now view no longer
/// diverges by platform.
struct HomeNowActiveContent: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let timerPickerMode: TimerPickerMode
    let actionLabelStyle: TaskTimerActionLabelStyle
    let openTask: (UUID) -> Void
    let startTimer: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ForEach(segments, id: \.id) { segment in
                ActiveTimerRow(
                    store: store,
                    segment: segment,
                    actionLabelStyle: actionLabelStyle,
                    openTaskDetail: openTask
                )
                .padding(12)
                .accessibilityIdentifier("home.activeTimer.\(segment.id.uuidString)")

                Divider()
                    .padding(.horizontal, 12)
            }

            HomeTimerPickerButton(
                mode: timerPickerMode,
                action: startTimer,
                accessibilityIdentifier: "home.startTimer"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct HomeTimerPickerButton: View {
    let mode: TimerPickerMode
    let action: () -> Void
    let accessibilityIdentifier: String

    var body: some View {
        Button(action: action) {
            Label {
                Text(mode.title)
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: mode.primaryActionSystemImage)
            }
            .font(.body.weight(.medium))
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 60, alignment: .leading)
            .contentShape(Rectangle())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(accessibilityIdentifier)
    }
}
