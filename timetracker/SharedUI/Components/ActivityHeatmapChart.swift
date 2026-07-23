import Charts
import SwiftUI

nonisolated enum ActivityHeatmapLayoutContext: Equatable, Sendable {
    case phone
    case regular
}

nonisolated struct ActivityHeatmapLayoutPolicy: Equatable, Sendable {
    private static let dayCount: CGFloat = 7

    let context: ActivityHeatmapLayoutContext
    let weekCount: Int

    var cellSize: CGFloat {
        switch (context, weekCount) {
        case (.phone, ...5):
            15
        case (.phone, ...14):
            12
        case (.phone, ...27):
            11
        case (.phone, _):
            10
        case (.regular, ...5):
            14
        case (.regular, ...14):
            11
        case (.regular, ...27):
            10
        case (.regular, _):
            9
        }
    }

    var cellSpacing: CGFloat { 3 }

    var chartWidth: CGFloat {
        let columns = CGFloat(max(1, weekCount))
        return columns * cellSize
            + max(0, columns - 1) * cellSpacing
            + 34
    }

    var chartHeight: CGFloat {
        let rows = Self.dayCount
        return rows * cellSize
            + (rows - 1) * cellSpacing
            + 27
    }
}

extension EnvironmentValues {
    @Entry var activityHeatmapLayoutContext: ActivityHeatmapLayoutContext = .regular
}

struct ActivityHeatmapChart: View {
    let snapshot: TaskActivityHeatmapSnapshot

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale
    @Environment(\.activityHeatmapLayoutContext)
    private var layoutContext

    private let cells: [ActivityHeatmapChartCell]

    init(snapshot: TaskActivityHeatmapSnapshot) {
        self.snapshot = snapshot
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
                width: .fixed(layoutPolicy.cellSize),
                height: .fixed(layoutPolicy.cellSize)
            )
            .foregroundStyle(fillColor(for: cell.day))
            .cornerRadius(2)
            .annotation(position: .overlay) {
                if cell.day.isToday {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(.primary.opacity(0.72), lineWidth: 1)
                        .frame(
                            width: layoutPolicy.cellSize,
                            height: layoutPolicy.cellSize
                        )
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
        .frame(
            width: layoutPolicy.chartWidth,
            height: layoutPolicy.chartHeight
        )
        .accessibilityIdentifier(
            "home.heatmap.chart.\(snapshot.taskID.uuidString)"
        )
    }

    private var palette: ActivityHeatmapPalette {
        ActivityHeatmapPalette(
            colorHex: snapshot.colorHex,
            colorScheme: colorScheme,
            colorSchemeContrast: colorSchemeContrast
        )
    }

    private var layoutPolicy: ActivityHeatmapLayoutPolicy {
        ActivityHeatmapLayoutPolicy(
            context: layoutContext,
            weekCount: snapshot.weeks.count
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
