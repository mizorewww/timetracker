import ActivityKit
import SwiftUI
import WidgetKit

struct TimeTrackingActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var taskTitle: String
        var taskPath: String
        var iconName: String
        var colorHex: String
        var startedAt: Date
        var additionalTimerCount: Int
    }

    var taskID: String
}

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
                .activityBackgroundTint(.black.opacity(0.82))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ActivityIconView(state: context.state, size: 44)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(startedAt: context.state.startedAt, style: .expanded)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(context.state.taskTitle)
                                .font(.headline.weight(.semibold))
                                .lineLimit(1)
                            if context.state.additionalTimerCount > 0 {
                                Text("+\(context.state.additionalTimerCount)")
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.white.opacity(0.16), in: Capsule())
                            }
                        }
                        Text(context.state.taskPath.isEmpty ? "正在记录时间" : context.state.taskPath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } compactLeading: {
                ActivityIconView(state: context.state, size: 24)
            } compactTrailing: {
                Text(context.state.startedAt, style: .timer)
                    .font(.caption2.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: 46)
            } minimal: {
                Image(systemName: context.state.iconName)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .frame(width: 22, height: 22)
                    .background(activityColor(context.state.colorHex), in: Circle())
            }
            .keylineTint(activityColor(context.state.colorHex))
        }
    }
}

private struct LockScreenTimerView: View {
    let context: ActivityViewContext<TimeTrackingActivityAttributes>

    var body: some View {
        HStack(spacing: 14) {
            ActivityIconView(state: context.state, size: 52)

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    Text(context.state.taskTitle)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    if context.state.additionalTimerCount > 0 {
                        Text("另有 \(context.state.additionalTimerCount) 个")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(.white.opacity(0.14), in: Capsule())
                    }
                }

                Text(context.state.taskPath.isEmpty ? "正在记录时间" : context.state.taskPath)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.66))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            TimerText(startedAt: context.state.startedAt, style: .lockScreen)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }
}

private struct ActivityIconView: View {
    let state: TimeTrackingActivityAttributes.ContentState
    let size: CGFloat

    var body: some View {
        ZStack {
            Circle()
                .fill(activityColor(state.colorHex).gradient)
            Circle()
                .stroke(.white.opacity(0.22), lineWidth: 1)
            Image(systemName: state.iconName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: size, height: size)
        .shadow(color: activityColor(state.colorHex).opacity(0.35), radius: 10, x: 0, y: 4)
    }
}

private struct TimerText: View {
    enum Style {
        case lockScreen
        case expanded
    }

    let startedAt: Date
    let style: Style

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(startedAt, style: .timer)
                .font(style == .lockScreen ? .title2.monospacedDigit().weight(.semibold) : .headline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
            Text("已计时")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.58))
        }
    }
}

private func activityColor(_ hex: String) -> Color {
    var value = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    if value.count == 3 {
        value = value.map { "\($0)\($0)" }.joined()
    }
    var int: UInt64 = 0
    Scanner(string: value).scanHexInt64(&int)
    let red = Double((int >> 16) & 0xFF) / 255
    let green = Double((int >> 8) & 0xFF) / 255
    let blue = Double(int & 0xFF) / 255
    return Color(red: red, green: green, blue: blue)
}
