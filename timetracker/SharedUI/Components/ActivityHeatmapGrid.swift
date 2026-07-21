import SwiftUI

struct ActivityHeatmapGrid: View {
    let snapshot: TaskActivityHeatmapSnapshot
    let accessibilitySummary: String

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                ActivityHeatmapChart(snapshot: snapshot)
                    .padding(.horizontal, 1)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing, for: .initialOffset)
            .defaultScrollAnchor(.leading, for: .alignment)

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

    private var rangeLabel: some View {
        Text(rangeText)
            .font(.caption)
            .foregroundStyle(.secondary)
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
