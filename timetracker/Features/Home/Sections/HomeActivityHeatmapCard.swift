import SwiftUI

struct TaskActivityHeatmapCard: View {
    let snapshot: TaskActivityHeatmapSnapshot

    @Environment(\.locale) private var locale

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            ActivityHeatmapGrid(
                snapshot: snapshot,
                accessibilitySummary: accessibilitySummary
            )
            .accessibilityIdentifier(
                "home.heatmap.grid.\(snapshot.taskID.uuidString)"
            )
            if snapshot.hasActivity == false {
                Text(noActivityExplanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(
            "home.heatmap.\(snapshot.taskID.uuidString)"
        )
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            TaskIcon(
                visual: TaskVisualPresentation(
                    iconName: snapshot.iconName,
                    colorHex: snapshot.colorHex
                ),
                size: 30
            )
            VStack(alignment: .leading, spacing: 2) {
                Text(snapshot.title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                Text(metricTitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Text(headerValue)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(Color(hex: snapshot.colorHex) ?? .blue)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .allowsTightening(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var metricTitle: String {
        switch snapshot.metric {
        case .trackedDuration:
            AppStrings.localized("home.heatmap.metric.duration")
        case .checklistCompletions:
            AppStrings.localized("home.heatmap.metric.checklist")
        case let .quantity(unitLabel):
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.metric.quantityFormat"),
                unitLabel
            )
        }
    }

    private var totalValue: String {
        ActivityHeatmapValueFormatter.compact(
            snapshot.totalValue,
            metric: snapshot.metric,
            locale: locale
        )
    }

    private var headerValue: String {
        switch snapshot.metric {
        case .quantity:
            snapshot.totalValue.formatted(.number.locale(locale))
        case .trackedDuration, .checklistCompletions:
            totalValue
        }
    }

    private var maximumDailyValue: String {
        ActivityHeatmapValueFormatter.compact(
            snapshot.maximumDailyValue,
            metric: snapshot.metric,
            locale: locale
        )
    }

    private var noActivityExplanation: String {
        String.localizedStringWithFormat(
            AppStrings.localized("home.heatmap.footer.noActivityFormat"),
            metricTitle
        )
    }

    private var accessibilitySummary: String {
        String.localizedStringWithFormat(
            AppStrings.localized("home.heatmap.accessibilitySummaryFormat"),
            metricTitle,
            totalValue,
            Int64(snapshot.activeDayCount),
            maximumDailyValue
        )
    }
}
