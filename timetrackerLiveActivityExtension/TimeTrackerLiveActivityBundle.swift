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
                .accessibilityIdentifier("liveActivity.compact.leading")
            } compactTrailing: {
                let timer = CompactTimerText(
                    startedAt: context.state.startedAt
                )
                Link(destination: LiveActivityDeepLinks.today) {
                    timer
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 50)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(
                    String(localized: context.isStale ? "live.timer.stale" : "live.timer.elapsed")
                )
                .accessibilityValue(timer.fullStopwatchText)
                .accessibilityHint(
                    context.isStale ? String(localized: "live.timer.staleHint") : ""
                )
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("liveActivity.compact.timer")
            } minimal: {
                let timer = CompactTimerText(
                    startedAt: context.state.startedAt
                )
                Link(destination: LiveActivityDeepLinks.today) {
                    timer
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.55)
                        .frame(maxWidth: 45)
                        .accessibilityHidden(true)
                }
                .accessibilityLabel(
                    String(localized: context.isStale ? "live.timer.stale" : "live.timer.elapsed")
                )
                .accessibilityValue(timer.fullStopwatchText)
                .accessibilityHint(
                    context.isStale ? String(localized: "live.timer.staleHint") : ""
                )
                .accessibilityAddTraits(.updatesFrequently)
                .accessibilityIdentifier("liveActivity.minimal.timer")
            }
            .keylineTint(activityColor(context.state.colorHex))
            .widgetURL(LiveActivityDeepLinks.today)
        }
    }
}
