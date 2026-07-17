import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

struct ExpandedActivityDetails: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let context: ActivityViewContext<TimeTrackingActivityAttributes>

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else {
                regularContent
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityContent: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(context.state.taskTitle)
                .font(.headline.weight(.semibold))
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
                .privacySensitive()

            LiveActivityStopButton(segmentID: context.attributes.segmentID)
        }
    }

    private var regularContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    title
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                    additionalTimerBadge
                }

                VStack(alignment: .leading, spacing: 3) {
                    title.lineLimit(2)
                    additionalTimerBadge
                }
            }

            Text(path(for: context.state))
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .privacySensitive()

            Button(intent: LiveActivityStopTimerIntent(
                segmentID: context.attributes.segmentID
            )) {
                Label(
                    String(localized: "live.timer.openToStop"),
                    systemImage: "arrow.up.forward.app"
                )
                    .font(.caption.weight(.semibold))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
        }
    }

    private var title: some View {
        Text(context.state.taskTitle)
            .font(.headline.weight(.semibold))
            .privacySensitive()
    }

    @ViewBuilder
    private var additionalTimerBadge: some View {
        if context.state.additionalTimerCount > 0 {
            Text(String.localizedStringWithFormat(
                String(localized: "live.timer.additionalFormat"),
                context.state.additionalTimerCount
            ))
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.white.opacity(0.16), in: Capsule())
        }
    }
}
