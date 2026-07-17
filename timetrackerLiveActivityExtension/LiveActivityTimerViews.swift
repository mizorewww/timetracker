import ActivityKit
import AppIntents
import Foundation
import SwiftUI
import WidgetKit

struct LockScreenTimerView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let context: ActivityViewContext<TimeTrackingActivityAttributes>

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else {
                ViewThatFits(in: .horizontal) {
                    wideContent
                    stackedContent
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var wideContent: some View {
        HStack(spacing: 12) {
            ActivityIconView(state: context.state, size: 48)
            ActivityTaskSummary(state: context.state, allowsWrapping: false)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 4)

            TimerText(
                startedAt: context.state.startedAt,
                isStale: context.isStale,
                style: .lockScreen
            )

            LiveActivityStopButton(segmentID: context.attributes.segmentID)
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(context.state.taskTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .privacySensitive()
                LiveActivityStopButton(segmentID: context.attributes.segmentID)
            }

            TimerText(
                startedAt: context.state.startedAt,
                isStale: context.isStale,
                style: .lockScreen
            )
        }
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ActivityIconView(state: context.state, size: 40)
                ActivityTaskSummary(state: context.state, allowsWrapping: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LiveActivityStopButton(segmentID: context.attributes.segmentID)
            }

            TimerText(
                startedAt: context.state.startedAt,
                isStale: context.isStale,
                style: .lockScreen
            )
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ActivityTaskSummary: View {
    let state: TimeTrackingActivityAttributes.ContentState
    let allowsWrapping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            if allowsWrapping {
                Text(state.taskTitle)
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .privacySensitive()
                additionalTimerBadge
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(state.taskTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .privacySensitive()
                    additionalTimerBadge
                }
            }

            Text(path(for: state))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(allowsWrapping ? 2 : 1)
                .privacySensitive()
        }
    }

    @ViewBuilder
    private var additionalTimerBadge: some View {
        if state.additionalTimerCount > 0 {
            Text(String.localizedStringWithFormat(
                String(localized: "live.timer.additionalFormat"),
                state.additionalTimerCount
            ))
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.9))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(.white.opacity(0.14), in: Capsule())
        }
    }
}

struct LiveActivityStopButton: View {
    let segmentID: String

    var body: some View {
        Button(intent: LiveActivityStopTimerIntent(segmentID: segmentID)) {
            Image(systemName: "arrow.up.forward.app")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(.white.opacity(0.16), in: Circle())
        }
        .accessibilityLabel(String(localized: "live.timer.openToStop"))
    }
}

struct ActivityIconView: View {
    let state: TimeTrackingActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(activityColor(state.colorHex).gradient)
            Circle()
                .stroke(activityForegroundColor(state.colorHex).opacity(0.24), lineWidth: 1)
            Image(systemName: state.iconName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(activityForegroundColor(state.colorHex))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
