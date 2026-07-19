import SwiftUI

struct AnalyticsFocusRoundsContent: View {
    private static let maximumRenderedRoundCount = 20

    let store: TimeTrackerStore
    let segmentIDs: [UUID]

    var body: some View {
        let segments = store.completedFocusRoundSegments(
            segmentIDs: Array(segmentIDs.prefix(Self.maximumRenderedRoundCount))
        )

        Group {
            if segments.isEmpty {
                EmptyStateRow(
                    title: AppStrings.localized("analytics.focusRounds.empty"),
                    icon: "timer"
                )
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    summary(for: segments)

                    VStack(spacing: 0) {
                        let lastSegmentID = segments.last?.id
                        ForEach(segments, id: \.id) { segment in
                            AnalyticsFocusRoundRow(
                                store: store,
                                segment: segment,
                                showsDivider: segment.id != lastSegmentID
                            )
                        }
                    }
                }
            }
        }
    }

    private func summary(for segments: [TimeSegment]) -> some View {
        let formatKey = segmentIDs.count == 1
            ? "analytics.focusRounds.showingSingularFormat"
            : "analytics.focusRounds.showingFormat"
        return Text(
            String(
                format: AppStrings.localized(formatKey),
                segments.count,
                segmentIDs.count
            )
        )
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityIdentifier("analytics.focusRounds.summary")
    }
}

private struct AnalyticsFocusRoundRow: View {
    let store: TimeTrackerStore
    let segment: TimeSegment
    let showsDivider: Bool

    var body: some View {
        VStack(spacing: 0) {
            TimelineRow(store: store, segment: segment)

            if showsDivider {
                Divider()
                    .padding(.leading, 18)
            }
        }
    }
}
