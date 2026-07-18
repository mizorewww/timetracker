import ActivityKit
import Foundation
import SwiftUI
import WidgetKit

@main
struct TimeTrackerLiveActivityBundle: WidgetBundle {
    var body: some Widget {
        TimeTrackerLiveActivityWidget()
    }
}

struct TimeTrackerLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimeTrackingActivityAttributes.self) { context in
            LockScreenTimerView(context: context)
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
                .widgetURL(LiveActivityDeepLinks.today)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedActivityDetails(context: context)
                }
            } compactLeading: {
                Link(destination: LiveActivityDeepLinks.today) {
                    HStack(spacing: 3) {
                        ActivityIconView(state: context.state, size: 18)
                        Text(context.state.taskTitle)
                            .font(.caption2.weight(.semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .privacySensitive()
                    }
                    .frame(maxWidth: 62, alignment: .leading)
                }
                .accessibilityLabel(context.state.taskTitle)
            } compactTrailing: {
                Link(destination: LiveActivityDeepLinks.today) {
                    CompactTimerText(
                        startedAt: context.state.startedAt,
                        isStale: context.isStale
                    )
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 50)
                }
                .accessibilityLabel(String(localized: "live.timer.elapsed"))
            } minimal: {
                Link(destination: LiveActivityDeepLinks.today) {
                    CompactTimerText(
                        startedAt: context.state.startedAt,
                        isStale: context.isStale
                    )
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: 45)
                }
                .accessibilityLabel(String(localized: "live.timer.elapsed"))
            }
            .keylineTint(activityColor(context.state.colorHex))
            .widgetURL(LiveActivityDeepLinks.today)
        }
    }
}
