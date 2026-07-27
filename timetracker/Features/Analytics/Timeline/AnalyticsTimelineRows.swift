import SwiftUI

extension OverlappingTimelineContent {
    @ViewBuilder
    func timelineLegendRow(_ entry: AnalyticsTimelineEntry) -> some View {
        switch entry.id {
        case .trackedSegment:
            Button {
                presentationRouter.presentEditSegment(
                    entry.id,
                    using: store
                )
            } label: {
                HStack(spacing: 8) {
                    TimelineLegendRow(entry: entry)
                    Image(systemName: "pencil")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 28)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(
                "analytics.timeline.entry.\(entry.id.namespacedKey)"
            )
            .accessibilityHint(
                AppStrings.localized("timeline.editSegment")
            )
        case .appleHealthWorkout, .appleHealthSleep:
            TimelineLegendRow(entry: entry)
                .accessibilityIdentifier(
                    "analytics.timeline.entry.\(entry.id.namespacedKey)"
                )
        }
    }
}
