import Charts
import SwiftUI

struct ActivityHeatmapGrid: View {
    let snapshot: TaskActivityHeatmapSnapshot
    let accessibilitySummary: String

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private let cells: [ActivityHeatmapChartCell]
    private let cellSize: CGFloat = 9
    private let cellSpacing: CGFloat = 3

    init(
        snapshot: TaskActivityHeatmapSnapshot,
        accessibilitySummary: String
    ) {
        self.snapshot = snapshot
        self.accessibilitySummary = accessibilitySummary
        cells = snapshot.weeks.enumerated().flatMap { weekIndex, week in
            week.days.enumerated().map { weekdayIndex, day in
                ActivityHeatmapChartCell(
                    day: day,
                    weekPosition: Double(weekIndex),
                    weekdayPosition: Double(6 - weekdayIndex)
                )
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ScrollView(.horizontal) {
                heatmapChart
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

    private var heatmapChart: some View {
        Chart(cells) { cell in
            RectangleMark(
                x: .value(
                    AppStrings.localized("home.heatmap.chart.week"),
                    cell.weekPosition
                ),
                y: .value(
                    AppStrings.localized("home.heatmap.chart.weekday"),
                    cell.weekdayPosition
                ),
                width: .fixed(cellSize),
                height: .fixed(cellSize)
            )
            .foregroundStyle(fillColor(for: cell.day))
            .cornerRadius(2)
            .annotation(position: .overlay) {
                if cell.day.isToday {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(.primary.opacity(0.72), lineWidth: 1)
                        .frame(width: cellSize, height: cellSize)
                }
            }
            .accessibilityLabel(accessibleDate(cell.day.date))
            .accessibilityValue(
                ActivityHeatmapValueFormatter.spoken(
                    cell.day.value,
                    metric: snapshot.metric,
                    locale: locale
                )
            )
            .accessibilityHidden(cell.day.isFuture)
        }
        .chartLegend(.hidden)
        .chartXScale(
            domain: -0.5...max(0.5, Double(snapshot.weeks.count) - 0.5),
            range: .plotDimension(startPadding: 1, endPadding: 1)
        )
        .chartYScale(
            domain: -0.5...6.5,
            range: .plotDimension(startPadding: 1, endPadding: 1)
        )
        .chartXAxis {
            AxisMarks(
                position: .top,
                values: monthMarkers.map(\.weekPosition)
            ) { value in
                AxisValueLabel(anchor: .topLeading) {
                    if let position = value.as(Double.self),
                       let marker = monthMarkers.first(where: {
                           $0.weekPosition == position
                       }) {
                        Text(
                            marker.date.formatted(
                                .dateTime.month(.abbreviated).locale(locale)
                            )
                        )
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: [0.0, 2.0, 4.0, 6.0]) { value in
                AxisValueLabel {
                    if let position = value.as(Double.self),
                       let date = weekdayDate(for: position) {
                        Text(
                            date.formatted(
                                .dateTime.weekday(.narrow).locale(locale)
                            )
                        )
                    }
                }
            }
        }
        .frame(width: chartWidth, height: 108)
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

    private var palette: ActivityHeatmapPalette {
        ActivityHeatmapPalette(
            colorHex: snapshot.colorHex,
            colorScheme: colorScheme,
            colorSchemeContrast: colorSchemeContrast
        )
    }

    private var chartWidth: CGFloat {
        let count = CGFloat(snapshot.weeks.count)
        return max(320, count * cellSize + max(0, count - 1) * cellSpacing + 34)
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

    private var monthMarkers: [ActivityHeatmapMonthMarker] {
        var previousMonth: DateComponents?
        return snapshot.weeks.enumerated().compactMap { index, week in
            guard let anchor = week.days.dropFirst(3).first?.date else {
                return nil
            }
            let month = calendar.dateComponents(
                [.era, .year, .month],
                from: anchor
            )
            guard month != previousMonth else { return nil }
            previousMonth = month
            return ActivityHeatmapMonthMarker(
                weekPosition: Double(index),
                date: anchor
            )
        }
    }

    private func weekdayDate(for position: Double) -> Date? {
        let index = 6 - Int(position.rounded())
        guard let days = snapshot.weeks.first?.days,
              days.indices.contains(index) else {
            return nil
        }
        return days[index].date
    }

    private func fillColor(for day: ActivityHeatmapDay) -> Color {
        day.isFuture ? .clear : palette.color(for: day.intensity)
    }

    private func accessibleDate(_ date: Date) -> String {
        date.formatted(
            .dateTime
                .weekday(.wide)
                .month(.wide)
                .day()
                .year()
                .locale(locale)
        )
    }
}

struct ActivityHeatmapPalettePreview: View {
    let colorHex: String

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 3) {
            ForEach(ActivityHeatmapIntensity.allCases, id: \.rawValue) { intensity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(palette.color(for: intensity))
                    .frame(width: 9, height: 9)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(AppStrings.localized("home.heatmap.palette.accessibilityLabel"))
        .accessibilityValue(TaskColorPalette.accessibilityName(for: colorHex))
    }

    private var palette: ActivityHeatmapPalette {
        ActivityHeatmapPalette(
            colorHex: colorHex,
            colorScheme: colorScheme,
            colorSchemeContrast: colorSchemeContrast
        )
    }
}

struct ActivityHeatmapPalette {
    let colorHex: String
    let colorScheme: ColorScheme
    let colorSchemeContrast: ColorSchemeContrast

    func color(for intensity: ActivityHeatmapIntensity) -> Color {
        if intensity == .none {
            return Color.secondary.opacity(emptyOpacity)
        }
        let opacity: Double = switch intensity {
        case .none: emptyOpacity
        case .low: colorScheme == .dark ? 0.42 : 0.32
        case .medium: colorScheme == .dark ? 0.60 : 0.50
        case .high: colorScheme == .dark ? 0.78 : 0.72
        case .maximum: 1
        }
        let contrastBoost = colorSchemeContrast == .increased ? 0.10 : 0
        return (Color(hex: colorHex) ?? .blue)
            .opacity(min(1, opacity + contrastBoost))
    }

    private var emptyOpacity: Double {
        if colorSchemeContrast == .increased {
            return colorScheme == .dark ? 0.30 : 0.20
        }
        return colorScheme == .dark ? 0.18 : 0.11
    }
}

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

private struct ActivityHeatmapChartCell: Identifiable {
    let day: ActivityHeatmapDay
    let weekPosition: Double
    let weekdayPosition: Double

    var id: Date { day.id }
}

private struct ActivityHeatmapMonthMarker: Identifiable {
    let weekPosition: Double
    let date: Date

    var id: Double { weekPosition }
}
