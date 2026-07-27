import SwiftUI

struct ActivityHeatmapGrid: View {
    let snapshot: TaskActivityHeatmapSnapshot
    let accessibilitySummary: String

    @Environment(\.locale) private var locale
    @State private var viewportWidth: CGFloat = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                ActivityHeatmapChart(
                    snapshot: snapshot,
                    availableWidth: chartAvailableWidth
                )
                .padding(.horizontal, 1)
            }
            .id(snapshot.interval.start)
            .scrollDisabled(!layoutPolicy.overflowsAvailableWidth)
            #if os(macOS)
                .scrollIndicators(.automatic)
            #else
                .scrollIndicators(.hidden)
            #endif
                .defaultScrollAnchor(.trailing, for: .initialOffset)
                .defaultScrollAnchor(.leading, for: .alignment)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.width
                } action: { width in
                    guard abs(viewportWidth - width) > 0.5 else { return }
                    viewportWidth = width
                }
                .accessibilityIdentifier(
                    "home.heatmap.scroller.\(snapshot.taskID.uuidString)"
                )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    rangeLabel
                    Spacer(minLength: 8)
                    intensityLegend
                }
                VStack(alignment: .leading, spacing: 6) {
                    rangeLabel
                    intensityLegend
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.chart.accessibilityLabel"),
                snapshot.title
            )
        )
        .accessibilityValue(accessibilitySummary)
    }

    private var chartAvailableWidth: CGFloat {
        guard viewportWidth.isFinite else { return 0 }
        return max(0, viewportWidth - 2)
    }

    private var layoutPolicy: ActivityHeatmapLayoutPolicy {
        ActivityHeatmapLayoutPolicy(
            availableWidth: chartAvailableWidth,
            weekCount: snapshot.weeks.count
        )
    }

    private var rangeLabel: some View {
        Text(rangeText)
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityIdentifier(
                "home.heatmap.range.\(snapshot.taskID.uuidString)"
            )
    }

    private var intensityLegend: some View {
        HStack(spacing: 4) {
            Text(.app("home.heatmap.less"))
            ActivityHeatmapPalettePreview(colorHex: snapshot.colorHex)
            Text(.app("home.heatmap.more"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var rangeText: String {
        let start = snapshot.interval.start.formatted(
            .dateTime.month(.abbreviated).year().locale(locale)
        )
        let end = snapshot.today.formatted(
            .dateTime.month(.abbreviated).day().year().locale(locale)
        )
        return String.localizedStringWithFormat(
            AppStrings.localized("home.heatmap.rangeFormat"),
            start,
            end
        )
    }
}
