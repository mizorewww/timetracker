import SwiftUI

struct AnalyticsPeriodNavigator: View {
    let range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    private var isCurrentPeriod: Bool {
        range.isCurrentPeriod(referenceDate, liveNow: liveNow)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                previousButton
                datePicker
                nextButton
                todayButton
            }

            VStack(alignment: .leading, spacing: 4) {
                datePicker
                HStack(spacing: 4) {
                    previousButton
                    todayButton
                    nextButton
                }
            }
        }
        .buttonStyle(.borderless)
        .accessibilityIdentifier("analytics.periodControl")
    }

    private var previousButton: some View {
        periodButton(
            label: AppStrings.localized("analytics.period.previous"),
            systemImage: "chevron.left",
            identifier: "analytics.period.previous",
            disabled: false
        ) {
            movePeriod(by: -1)
        }
    }

    private var datePicker: some View {
        DatePicker(
            AppStrings.localized("analytics.period.select"),
            selection: $referenceDate,
            in: ...liveNow,
            displayedComponents: .date
        )
        .labelsHidden()
        .frame(minHeight: 44)
        .accessibilityIdentifier("analytics.period.date")
    }

    private var nextButton: some View {
        periodButton(
            label: AppStrings.localized("analytics.period.next"),
            systemImage: "chevron.right",
            identifier: "analytics.period.next",
            disabled: isCurrentPeriod
        ) {
            movePeriod(by: 1)
        }
    }

    private var todayButton: some View {
        Button {
            referenceDate = liveNow
        } label: {
            ViewThatFits(in: .horizontal) {
                Label(AppStrings.localized("analytics.period.today"), systemImage: "calendar")
                    .frame(minHeight: 44)
                Label(AppStrings.localized("analytics.period.today"), systemImage: "calendar")
                    .labelStyle(.iconOnly)
                    .frame(width: 44, height: 44)
            }
        }
        .disabled(isCurrentPeriod)
        .accessibilityLabel(AppStrings.localized("analytics.period.returnToToday"))
        .accessibilityIdentifier("analytics.period.today")
        .help(AppStrings.localized("analytics.period.returnToToday"))
    }

    private func periodButton(
        label: String,
        systemImage: String,
        identifier: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .disabled(disabled)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
        .help(label)
    }

    private func movePeriod(by value: Int) {
        referenceDate = AnalyticsPeriodNavigation.date(
            byMoving: value,
            range: range,
            referenceDate: referenceDate,
            liveNow: liveNow
        )
    }
}

enum AnalyticsPeriodText {
    static func title(
        for range: AnalyticsRange,
        date: Date,
        liveNow: Date,
        calendar: Calendar = .current
    ) -> String {
        switch range {
        case .today:
            if calendar.isDate(date, inSameDayAs: liveNow) {
                return AppStrings.localized("analytics.period.today")
            }
            if let yesterday = calendar.date(byAdding: .day, value: -1, to: liveNow),
               calendar.isDate(date, inSameDayAs: yesterday) {
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

enum AnalyticsPeriodNavigation {
    static func date(
        byMoving value: Int,
        range: AnalyticsRange,
        referenceDate: Date,
        liveNow: Date,
        calendar: Calendar = .current
    ) -> Date {
        let next = range.date(byAdding: value, to: referenceDate, calendar: calendar) ?? referenceDate
        return min(next, liveNow)
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

struct AnalyticsSnapshotRequest: Hashable {
    let range: AnalyticsRange
    let periodStart: Date
    let revision: UInt
    let liveRefreshBucket: Int?

    init(
        range: AnalyticsRange,
        referenceDate: Date,
        revision: UInt,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        self.range = range
        periodStart = range.interval(containing: referenceDate, calendar: calendar)?.start ?? referenceDate
        self.revision = revision
        self.liveRefreshBucket = liveRefreshBucket
    }
}

struct TaskAnalyticsSnapshotRequest: Hashable {
    let taskID: UUID
    let range: AnalyticsRange
    let periodStart: Date
    let revision: UInt
    let liveRefreshBucket: Int?

    init(
        taskID: UUID,
        range: AnalyticsRange,
        referenceDate: Date,
        revision: UInt,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        self.taskID = taskID
        self.range = range
        periodStart = range.interval(containing: referenceDate, calendar: calendar)?.start ?? referenceDate
        self.revision = revision
        self.liveRefreshBucket = liveRefreshBucket
    }
}
