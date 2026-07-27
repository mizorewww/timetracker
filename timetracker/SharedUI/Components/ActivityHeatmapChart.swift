import Charts
import SwiftUI

nonisolated struct ActivityHeatmapLayoutPolicy: Equatable, Sendable {
    static let minimumCellSize: CGFloat = 12
    static let maximumCellSize: CGFloat = 24

    private static let dayCount: CGFloat = 7
    private static let horizontalAxisReserve: CGFloat = 34
    private static let verticalAxisReserve: CGFloat = 27

    let availableWidth: CGFloat
    let weekCount: Int

    var cellSize: CGFloat {
        guard normalizedAvailableWidth > 0 else {
            return Self.minimumCellSize
        }

        for candidate in stride(
            from: Int(Self.maximumCellSize),
            through: Int(Self.minimumCellSize),
            by: -1
        ) {
            let size = CGFloat(candidate)
            if chartWidth(cellSize: size) <= normalizedAvailableWidth {
                return size
            }
        }
        return Self.minimumCellSize
    }

    var cellSpacing: CGFloat {
        Self.cellSpacing(for: cellSize)
    }

    var chartWidth: CGFloat {
        chartWidth(cellSize: cellSize)
    }

    var chartHeight: CGFloat {
        let rows = Self.dayCount
        return rows * cellSize
            + (rows - 1) * cellSpacing
            + Self.verticalAxisReserve
    }

    var overflowsAvailableWidth: Bool {
        guard normalizedAvailableWidth > 0 else { return false }
        return chartWidth > normalizedAvailableWidth + 0.5
    }

    private var normalizedAvailableWidth: CGFloat {
        guard availableWidth.isFinite, availableWidth > 0 else { return 0 }
        return availableWidth
    }

    private func chartWidth(cellSize: CGFloat) -> CGFloat {
        let columns = CGFloat(max(1, weekCount))
        return columns * cellSize
            + max(0, columns - 1) * Self.cellSpacing(for: cellSize)
            + Self.horizontalAxisReserve
    }

    private static func cellSpacing(for cellSize: CGFloat) -> CGFloat {
        switch cellSize {
        case ...13:
            2
        case ...19:
            3
        default:
            4
        }
    }
}

struct ActivityHeatmapChart: View {
    let snapshot: TaskActivityHeatmapSnapshot
    let availableWidth: CGFloat

    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private let cells: [ActivityHeatmapChartCell]

    init(
        snapshot: TaskActivityHeatmapSnapshot,
        availableWidth: CGFloat
    ) {
        self.snapshot = snapshot
        self.availableWidth = availableWidth
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
            // Per-cell accessibility elements cost a formatted date string
            // and an AX node for every one of the 371 marks; the card-level
            // summary already describes the whole heatmap.
            .accessibilityHidden(true)
        }
        .chartLegend(.hidden)
        .chartXScale(
            domain: -0.5 ... max(0.5, Double(snapshot.weeks.count) - 0.5),
            range: .plotDimension(startPadding: 1, endPadding: 1)
        )
        .chartYScale(
            domain: -0.5 ... 6.5,
            range: .plotDimension(startPadding: 1, endPadding: 1)
        )
        .chartXAxis {
            AxisMarks(
                position: .top,
                values: monthMarkers.map(\.weekPosition)
            ) { value in
                AxisValueLabel(
                    anchor: .topLeading,
                    collisionResolution: .greedy(
                        priority: 1,
                        minimumSpacing: 6
                    )
                ) {
                    if let position = value.as(Double.self),
                       let marker = monthMarkers.first(where: {
                           $0.weekPosition == position
                       })
                    {
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
                       let date = weekdayDate(for: position)
                    {
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
            availableWidth: availableWidth,
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
              days.indices.contains(index)
        else {
            return nil
        }
        return days[index].date
    }

    private func fillColor(for day: ActivityHeatmapDay) -> Color {
        day.isFuture ? .clear : palette.color(for: day.intensity)
    }
}

private struct ActivityHeatmapChartCell: Identifiable {
    let day: ActivityHeatmapDay
    let weekPosition: Double
    let weekdayPosition: Double

    var id: Date {
        day.id
    }
}

private struct ActivityHeatmapMonthMarker: Identifiable {
    let weekPosition: Double
    let date: Date

    var id: Double {
        weekPosition
    }
}
