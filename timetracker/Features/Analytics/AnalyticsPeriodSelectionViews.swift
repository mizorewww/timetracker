import SwiftUI

struct AnalyticsPeriodControl: View {
    let range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    private var isCurrentPeriod: Bool {
        range.isCurrentPeriod(referenceDate, liveNow: liveNow)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                controls
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(AnalyticsPeriodText.title(for: range, date: referenceDate))
                    .font(.subheadline.weight(.semibold))
                HStack(spacing: 8) {
                    controls
                }
            }
        }
        .accessibilityIdentifier("analytics.periodControl")
    }

    private var controls: some View {
        Group {
            Button {
                movePeriod(by: -1)
            } label: {
                Image(systemName: "chevron.left")
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel(AppStrings.localized("analytics.period.previous"))

            DatePicker(
                AppStrings.localized("analytics.period.select"),
                selection: $referenceDate,
                in: ...liveNow,
                displayedComponents: .date
            )
            .labelsHidden()

            Button {
                movePeriod(by: 1)
            } label: {
                Image(systemName: "chevron.right")
                    .frame(width: 32, height: 32)
            }
            .disabled(isCurrentPeriod)
            .accessibilityLabel(AppStrings.localized("analytics.period.next"))

            Button {
                referenceDate = liveNow
            } label: {
                Label(AppStrings.localized("analytics.period.current"), systemImage: "calendar")
            }
            .disabled(isCurrentPeriod)
        }
    }

    private func movePeriod(by value: Int) {
        let next = range.date(byAdding: value, to: referenceDate) ?? referenceDate
        referenceDate = min(next, liveNow)
    }
}

enum AnalyticsPeriodText {
    static func title(for range: AnalyticsRange, date: Date, calendar: Calendar = .current) -> String {
        switch range {
        case .today:
            if calendar.isDateInToday(date) {
                return AppStrings.localized("analytics.period.today")
            }
            if calendar.isDateInYesterday(date) {
                return AppStrings.localized("analytics.period.yesterday")
            }
            return DateFormatter.localizedString(from: date, dateStyle: .medium, timeStyle: .none)
        case .week:
            let start = range.interval(containing: date, calendar: calendar)?.start ?? date
            let label = DateFormatter.localizedString(from: start, dateStyle: .medium, timeStyle: .none)
            return String(format: AppStrings.localized("analytics.period.weekOfFormat"), label)
        case .month:
            return date.formatted(.dateTime.month(.wide).year())
        }
    }
}

extension AnalyticsRange {
    func interval(containing date: Date, calendar: Calendar = .current) -> DateInterval? {
        switch self {
        case .today:
            return calendar.dateInterval(of: .day, for: date)
        case .week:
            return calendar.dateInterval(of: .weekOfYear, for: date)
        case .month:
            return calendar.dateInterval(of: .month, for: date)
        }
    }

    func effectiveSnapshotDate(referenceDate: Date, liveNow: Date, calendar: Calendar = .current) -> Date {
        guard let selectedInterval = interval(containing: referenceDate, calendar: calendar) else {
            return liveNow
        }
        if selectedInterval.contains(liveNow) {
            return liveNow
        }
        return selectedInterval.end.addingTimeInterval(-1)
    }

    func isCurrentPeriod(_ date: Date, liveNow: Date, calendar: Calendar = .current) -> Bool {
        guard let selected = interval(containing: date, calendar: calendar),
              let current = interval(containing: liveNow, calendar: calendar) else {
            return false
        }
        return selected.start == current.start
    }

    func date(byAdding value: Int, to date: Date, calendar: Calendar = .current) -> Date? {
        switch self {
        case .today:
            return calendar.date(byAdding: .day, value: value, to: date)
        case .week:
            return calendar.date(byAdding: .weekOfYear, value: value, to: date)
        case .month:
            return calendar.date(byAdding: .month, value: value, to: date)
        }
    }
}
