import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

struct LockScreenTimerView: View {
    let context: ActivityViewContext<TimeTrackingActivityAttributes>

    var body: some View {
        HStack(spacing: 12) {
            ActivityIconView(state: context.state, size: 48)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(context.state.taskTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .privacySensitive()
                    if context.state.additionalTimerCount > 0 {
                        Text(String.localizedStringWithFormat(
                            String(localized: "live.timer.additionalFormat"),
                            context.state.additionalTimerCount
                        ))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(.white.opacity(0.14), in: Capsule())
                    }
                }

                Text(path(for: context.state))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
                    .privacySensitive()
            }

            Spacer(minLength: 4)

            TimerText(
                startedAt: context.state.startedAt,
                isStale: context.isStale,
                style: .lockScreen
            )

            Link(destination: LiveActivityDeepLinks.stopTimer(taskID: context.attributes.taskID)) {
                Image(systemName: "stop.fill")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(.white.opacity(0.16), in: Circle())
            }
            .accessibilityLabel(String(localized: "live.timer.stop"))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

struct TimerText: View {
    enum Style {
        case lockScreen
        case expanded
    }

    let startedAt: Date
    let isStale: Bool
    let style: Style

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(startedAt, style: .timer)
                .font(
                    style == .lockScreen
                        ? .title2.monospacedDigit().weight(.semibold)
                        : .headline.monospacedDigit().weight(.semibold)
                )
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Label(
                String(localized: isStale ? "live.timer.stale" : "live.timer.elapsed"),
                systemImage: isStale ? "exclamationmark.clock" : "clock"
            )
            .labelStyle(.titleAndIcon)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.66))
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: isStale ? "live.timer.stale" : "live.timer.elapsed"))
        .accessibilityValue(Text(startedAt, style: .timer))
    }
}
