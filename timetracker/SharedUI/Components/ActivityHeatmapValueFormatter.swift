import Foundation

enum ActivityHeatmapValueFormatter {
    static func compact(
        _ value: Int,
        metric: ActivityHeatmapMetric,
        locale: Locale
    ) -> String {
        switch metric {
        case .trackedDuration:
            DurationFormatter.chart(value, locale: locale)
        case .checklistCompletions:
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.checklistValueFormat"),
                Int64(value)
            )
        case let .quantity(unitLabel):
            String.localizedStringWithFormat(
                AppStrings.localized("home.heatmap.quantityValueFormat"),
                Int64(value),
                unitLabel
            )
        }
    }

    static func spoken(
        _ value: Int,
        metric: ActivityHeatmapMetric,
        locale: Locale
    ) -> String {
        switch metric {
        case .trackedDuration:
            DurationFormatter.spoken(value, locale: locale)
        case .checklistCompletions, .quantity:
            compact(value, metric: metric, locale: locale)
        }
    }
}
