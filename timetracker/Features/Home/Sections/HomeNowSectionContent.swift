import SwiftUI

/// Shared Now content used by every platform: iPhone hosts it in a grouped
/// list section, iPad and macOS in an app card, so the Now view no longer
/// diverges by platform.
struct HomeNowActiveContent: View {
    let store: TimeTrackerStore
    let segments: [TimeSegment]
    let allowsParallelTimers: Bool
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

            Button(action: startTimer) {
                Label {
                    Text(activeTimerActionTitle)
                        .lineLimit(nil)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: activeTimerActionSystemImage)
                }
                .font(.body.weight(.medium))
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .accessibilityIdentifier("home.startTimer")
        }
    }

    private var activeTimerActionTitle: String {
        allowsParallelTimers
            ? AppStrings.localized("home.startAnotherTimer")
            : AppStrings.localized("home.switchTimer")
    }

    private var activeTimerActionSystemImage: String {
        allowsParallelTimers ? "plus.circle" : "arrow.left.arrow.right.circle"
    }
}

struct HomeNowEmptyStartButton: View {
    let startTimer: () -> Void

    var body: some View {
        Button(action: startTimer) {
            AppActionLabel(
                title: AppStrings.startTimer,
                systemImage: "play.fill",
                minHeight: 48
            )
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .accessibilityIdentifier("home.startTimer")
    }
}
