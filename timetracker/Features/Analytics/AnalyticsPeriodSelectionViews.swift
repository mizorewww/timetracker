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
                    .frame(minWidth: 44, minHeight: 44)
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
                .frame(minWidth: 44, minHeight: 44)
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
            return formattedDate(date, dateStyle: .medium, calendar: calendar)
        case .week:
            let start = range.interval(containing: date, calendar: calendar)?.start ?? date
            let label = formattedDate(start, dateStyle: .medium, calendar: calendar)
            return String(format: AppStrings.localized("analytics.period.weekOfFormat"), label)
        case .month:
            let formatter = formatter(calendar: calendar)
            formatter.setLocalizedDateFormatFromTemplate("MMMM y")
            return formatter.string(from: date)
        }
    }

    private static func formattedDate(
        _ date: Date,
        dateStyle: DateFormatter.Style,
        calendar: Calendar
    ) -> String {
        let formatter = formatter(calendar: calendar)
        formatter.dateStyle = dateStyle
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    private static func formatter(calendar: Calendar) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = calendar.locale ?? .current
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        return formatter
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

nonisolated struct AnalyticsSnapshotRequest: Hashable, Sendable {
    let range: AnalyticsRange
    let periodStart: Date
    let revision: UInt
    let liveRefreshBucket: Int?

    init(
        range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        revision: UInt,
        liveRefreshBucket: Int?
    ) {
        self.range = range
        periodStart = evaluation.interval.start
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
