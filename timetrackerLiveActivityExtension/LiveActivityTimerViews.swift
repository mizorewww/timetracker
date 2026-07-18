import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

struct LockScreenTimerView: View {
    let context: ActivityViewContext<TimeTrackingActivityAttributes>

    var body: some View {
        LiveActivityTimerRow(
            state: context.state,
            isStale: context.isStale,
            style: .lockScreen
        )
        .padding(14)
    }
}

enum LiveActivityTimerRowStyle {
    case lockScreen
    case dynamicIsland

    var iconSize: CGFloat {
        switch self {
        case .lockScreen:
            34
        case .dynamicIsland:
            30
        }
    }

    var showsPath: Bool {
        self == .lockScreen
    }

    var timerStyle: TimerText.Style {
        switch self {
        case .lockScreen:
            .lockScreen
        case .dynamicIsland:
            .expanded
        }
    }
}

struct LiveActivityTimerRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let state: TimeTrackingActivityAttributes.ContentState
    let isStale: Bool
    let style: LiveActivityTimerRowStyle

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                stackedContent
            } else {
                ViewThatFits(in: .horizontal) {
                    horizontalContent
                    stackedContent
                }
            }
        }
    }

    private var horizontalContent: some View {
        HStack(alignment: .center, spacing: 10) {
            ActivityIconView(state: state, size: style.iconSize)

            ActivityTaskSummary(
                state: state,
                showsPath: style.showsPath,
                allowsWrapping: false
            )

            Spacer(minLength: 6)

            timer
                .layoutPriority(2)
        }
    }

    private var stackedContent: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                ActivityIconView(state: state, size: style.iconSize)

                ActivityTaskSummary(
                    state: state,
                    showsPath: style.showsPath,
                    allowsWrapping: true
                )
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            timer
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var timer: some View {
        TimerText(
            startedAt: state.startedAt,
            isStale: isStale,
            style: style.timerStyle
        )
    }
}

struct ActivityTaskSummary: View {
    let state: TimeTrackingActivityAttributes.ContentState
    let showsPath: Bool
    let allowsWrapping: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(state.taskTitle)
                .font(.headline.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(allowsWrapping ? 2 : 1)
                .privacySensitive()

            if showsPath {
                ViewThatFits(in: .horizontal) {
                    Text(path(for: state))
                        .fixedSize(horizontal: true, vertical: false)
                    Text(abbreviatedPath(for: state))
                }
                .font(.caption)
                .foregroundStyle(.white.opacity(0.66))
                .lineLimit(1)
                .truncationMode(.middle)
                .privacySensitive()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }
}

struct ActivityIconView: View {
    let state: TimeTrackingActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        let shape = RoundedRectangle(
            cornerRadius: size * 0.24,
            style: .continuous
        )
        ZStack {
            shape
                .fill(activityColor(state.colorHex).gradient)
            shape
                .stroke(activityForegroundColor(state.colorHex).opacity(0.24), lineWidth: 1)
            Image(systemName: state.iconName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(activityForegroundColor(state.colorHex))
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
