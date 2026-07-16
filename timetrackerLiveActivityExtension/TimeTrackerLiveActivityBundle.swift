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
                    ExpandedActivityDetails(context: context)
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
