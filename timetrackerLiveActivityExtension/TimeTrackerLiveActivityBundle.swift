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
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIconView(state: context.state, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(
                        startedAt: context.state.startedAt,
                        isStale: context.isStale,
                        style: .expanded
                    )
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(context.state.taskTitle)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                                .privacySensitive()
                            if context.state.additionalTimerCount > 0 {
                                Text("+\(context.state.additionalTimerCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.16), in: Capsule())
                            }
                        }

                        Text(path(for: context.state))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .privacySensitive()

                        Link(destination: LiveActivityDeepLinks.stopTimer(taskID: context.attributes.taskID)) {
                            Label(String(localized: "live.timer.stop"), systemImage: "stop.fill")
                                .font(.caption.weight(.semibold))
                                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                                .contentShape(Rectangle())
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                Link(destination: LiveActivityDeepLinks.today) {
                    ActivityIconView(state: context.state, size: 24)
                }
                .accessibilityLabel(String(localized: "live.timer.open"))
            } compactTrailing: {
                Link(destination: LiveActivityDeepLinks.today) {
                    Text(context.state.startedAt, style: .timer)
                        .font(.caption2.monospacedDigit().weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .frame(maxWidth: 50)
                }
                .accessibilityLabel(String(localized: "live.timer.elapsed"))
                .accessibilityValue(Text(context.state.startedAt, style: .timer))
            } minimal: {
                Link(destination: LiveActivityDeepLinks.today) {
                    ActivityIconView(state: context.state, size: 25)
                }
                .accessibilityLabel(String(localized: "live.timer.open"))
            }
            .keylineTint(activityColor(context.state.colorHex))
            .widgetURL(LiveActivityDeepLinks.today)
        }
    }
}
