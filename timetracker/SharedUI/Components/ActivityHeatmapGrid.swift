import SwiftUI

struct ActivityHeatmapGrid: View {
    let snapshot: ActivityHeatmapSnapshot
    let accessibilityTitle: String
    let accessibilitySummary: String

    @Environment(\.calendar) private var calendar
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.locale) private var locale

    private let cellSize: CGFloat = 9
    private let cellSpacing: CGFloat = 3
    private let weekdayLabelWidth: CGFloat = 18
    private let monthLabelHeight: CGFloat = 14

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 7) {
                weekdayLabels
                ScrollView(.horizontal) {
                    calendarGrid
                        .padding(.vertical, 1)
                }
                .scrollIndicators(.hidden)
                .defaultScrollAnchor(.trailing, for: .initialOffset)
                .defaultScrollAnchor(.leading, for: .alignment)
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(rangeLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                intensityLegend
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityTitle)
        .accessibilityValue(accessibilitySummary)
    }

    private var weekdayLabels: some View {
        VStack(spacing: cellSpacing) {
            Color.clear
                .frame(width: weekdayLabelWidth, height: monthLabelHeight)
            ForEach(weekdayRows) { row in
                Text(
                    row.showsLabel
                        ? weekdayLabel(for: row.day.date)
                        : ""
                )
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(
                        width: weekdayLabelWidth,
                        height: cellSize,
                        alignment: .trailing
                    )
            }
        }
    }

    private var calendarGrid: some View {
        VStack(alignment: .leading, spacing: cellSpacing) {
            monthLabels
            HStack(alignment: .top, spacing: cellSpacing) {
                ForEach(snapshot.weeks) { week in
                    VStack(spacing: cellSpacing) {
                        ForEach(week.days) { day in
                            heatmapCell(day)
                        }
                    }
                }
            }
        }
    }

    private var monthLabels: some View {
        ZStack(alignment: .topLeading) {
            Color.clear
                .frame(width: gridWidth, height: monthLabelHeight)
            ForEach(monthMarkers) { marker in
                Text(
                    marker.date.formatted(
                        .dateTime.month(.abbreviated).locale(locale)
                    )
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize()
                .offset(
                    x: CGFloat(marker.weekIndex) * (cellSize + cellSpacing)
                )
            }
        }
        .frame(width: gridWidth, height: monthLabelHeight, alignment: .leading)
        .clipped()
    }

    private func heatmapCell(_ day: ActivityHeatmapDay) -> some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(fillColor(for: day))
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if day.isToday {
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .stroke(.primary.opacity(0.7), lineWidth: 1)
                }
            }
            .accessibilityHidden(true)
    }

    private var intensityLegend: some View {
        HStack(spacing: 3) {
            Text(.app("home.heatmap.less"))
            ForEach(ActivityHeatmapIntensity.allCases, id: \.rawValue) {
                intensity in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(fillColor(for: intensity))
                    .frame(width: cellSize, height: cellSize)
            }
            Text(.app("home.heatmap.more"))
        }
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize()
        .accessibilityHidden(true)
    }

    private var firstWeekDays: [ActivityHeatmapDay] {
        snapshot.weeks.first?.days ?? []
    }

    private var weekdayRows: [ActivityHeatmapWeekdayRow] {
        firstWeekDays.enumerated().map { index, day in
            ActivityHeatmapWeekdayRow(
                day: day,
                showsLabel: index.isMultiple(of: 2)
            )
        }
    }

    private var gridWidth: CGFloat {
        let count = CGFloat(snapshot.weeks.count)
        return max(0, count * cellSize + max(0, count - 1) * cellSpacing)
    }

    private var rangeLabel: String {
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

    private func weekdayLabel(for date: Date) -> String {
        date.formatted(.dateTime.weekday(.narrow).locale(locale))
    }

    private func fillColor(for day: ActivityHeatmapDay) -> Color {
        day.isFuture ? .clear : fillColor(for: day.intensity)
    }

    private func fillColor(
        for intensity: ActivityHeatmapIntensity
    ) -> Color {
        let opacity: Double = switch intensity {
        case .none: colorScheme == .dark ? 0.18 : 0.11
        case .low: colorScheme == .dark ? 0.36 : 0.28
        case .medium: colorScheme == .dark ? 0.54 : 0.46
        case .high: colorScheme == .dark ? 0.74 : 0.68
        case .maximum: 0.96
        }
        return intensity == .none
            ? Color.secondary.opacity(opacity)
            : AppColors.grossTime.opacity(opacity)
    }
}

private struct ActivityHeatmapMonthMarker: Identifiable {
    let weekIndex: Int
    let date: Date

    var id: Int { weekIndex }
}

private struct ActivityHeatmapWeekdayRow: Identifiable {
    let day: ActivityHeatmapDay
    let showsLabel: Bool

    var id: Date { day.id }
}

private extension ActivityHeatmapGrid {
    var monthMarkers: [ActivityHeatmapMonthMarker] {
        var previousMonth: DateComponents?
        return snapshot.weeks.enumerated().compactMap { index, week in
            guard let anchor = week.days.dropFirst(3).first?.date else {
                return nil
            }
            let month = calendar.dateComponents([.era, .year, .month], from: anchor)
            guard month != previousMonth else { return nil }
            previousMonth = month
            return ActivityHeatmapMonthMarker(weekIndex: index, date: anchor)
        }
    }
}
