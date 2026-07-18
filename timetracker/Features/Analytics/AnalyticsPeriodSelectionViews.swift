import SwiftUI

struct AnalyticsPeriodNavigator: View {
    let range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date
    @Binding var monthNavigationAnchor: AnalyticsMonthNavigationAnchor?

    private var isCurrentPeriod: Bool {
        range.isCurrentPeriod(referenceDate, liveNow: liveNow)
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 4) {
                previousButton
                datePicker
                nextButton
                returnToTodayButton
            }

            VStack(alignment: .leading, spacing: 4) {
                datePicker
                HStack(spacing: 4) {
                    previousButton
                    returnToTodayButton
                    nextButton
                }
            }
        }
        .buttonStyle(.borderless)
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
            selection: dateSelection,
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

    @ViewBuilder
    private var returnToTodayButton: some View {
        if isCurrentPeriod == false {
            todayButton
        }
    }

    private var todayButton: some View {
        Button {
            monthNavigationAnchor = nil
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

    private var dateSelection: Binding<Date> {
        Binding(
            get: { referenceDate },
            set: { selectedDate in
                monthNavigationAnchor = nil
                referenceDate = selectedDate
            }
        )
    }

    private func movePeriod(by value: Int) {
        var anchor = monthNavigationAnchor
        let destination = AnalyticsPeriodNavigation.date(
            byMoving: value,
            range: range,
            referenceDate: referenceDate,
            liveNow: liveNow,
            monthAnchor: &anchor
        )
        monthNavigationAnchor = anchor
        referenceDate = destination
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
        monthAnchor: inout AnalyticsMonthNavigationAnchor?,
        calendar: Calendar = .current
    ) -> Date {
        guard range == .month else {
            monthAnchor = nil
            let next = range.date(byAdding: value, to: referenceDate, calendar: calendar)
                ?? referenceDate
            return min(next, liveNow)
        }

        let anchor = monthAnchor
            ?? AnalyticsMonthNavigationAnchor(referenceDate: referenceDate, calendar: calendar)
        monthAnchor = anchor

        guard let targetMonthStart = range.date(
            byAdding: value,
            to: referenceDate,
            calendar: calendar
        ),
              let targetMonth = range.interval(
                  containing: targetMonthStart,
                  calendar: calendar
              ),
              let currentMonth = range.interval(containing: liveNow, calendar: calendar) else {
            return min(referenceDate, liveNow)
        }

        guard targetMonth.start < currentMonth.start else {
            monthAnchor = nil
            return liveNow
        }

        let next = anchor.date(in: targetMonth, calendar: calendar) ?? targetMonth.start
        return min(next, liveNow)
    }
}

nonisolated struct AnalyticsMonthNavigationAnchor: Hashable, Sendable {
    let day: Int
    let hour: Int
    let minute: Int
    let second: Int

    init(referenceDate: Date, calendar: Calendar) {
        let components = calendar.dateComponents(
            [.day, .hour, .minute, .second],
            from: referenceDate
        )
        day = components.day ?? 1
        hour = components.hour ?? 0
        minute = components.minute ?? 0
        second = components.second ?? 0
    }

    func date(in month: DateInterval, calendar: Calendar) -> Date? {
        guard let validDays = calendar.range(of: .day, in: .month, for: month.start) else {
            return nil
        }
        // Clamp only this destination; retaining `day` lets a later, longer
        // month recover the original selection (Jan 31 → Feb 28 → Mar 31).
        let clampedDay = min(max(day, validDays.lowerBound), validDays.upperBound - 1)
        guard let targetDay = calendar.date(
            byAdding: .day,
            value: clampedDay - validDays.lowerBound,
            to: month.start
        ),
              let anchoredDate = calendar.date(
                  bySettingHour: hour,
                  minute: minute,
                  second: second,
                  of: targetDay,
                  matchingPolicy: .nextTimePreservingSmallerComponents,
                  repeatedTimePolicy: .first,
                  direction: .forward
              ),
              month.contains(anchoredDate) else {
            return nil
        }
        return anchoredDate
    }
}

nonisolated struct AnalyticsSnapshotRequest: Hashable, Sendable {
    let range: AnalyticsRange
    let evaluationKey: AnalyticsEvaluationCacheKey
    let revision: UInt

    init(
        range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        revision: UInt,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        self.range = range
        evaluationKey = AnalyticsEvaluationCacheKey(
            evaluation: evaluation,
            liveRefreshBucket: liveRefreshBucket,
            calendar: calendar
        )
        self.revision = revision
    }

    /// A snapshot can remain visible only while the selected calendar period
    /// itself is unchanged. Revisions and live buckets may advance within that
    /// period, but a range or interval change must never present old metrics
    /// under the newly selected controls.
    func canRemainVisible(whileLoading request: AnalyticsSnapshotRequest) -> Bool {
        range == request.range && evaluationKey.interval == request.evaluationKey.interval
    }
}

struct TaskAnalyticsSnapshotRequest: Hashable {
    let taskID: UUID
    let taskIDs: Set<UUID>
    let range: AnalyticsRange
    let evaluationKey: AnalyticsEvaluationCacheKey
    let revision: UInt

    var liveRefreshBucket: Int? { evaluationKey.liveRefreshBucket }

    init(
        taskID: UUID,
        taskIDs: Set<UUID>,
        range: AnalyticsRange,
        evaluation: AnalyticsPeriodEvaluation,
        revision: UInt,
        liveRefreshBucket: Int?,
        calendar: Calendar = .current
    ) {
        self.taskID = taskID
        self.taskIDs = taskIDs
        self.range = range
        evaluationKey = AnalyticsEvaluationCacheKey(
            evaluation: evaluation,
            liveRefreshBucket: liveRefreshBucket,
            calendar: calendar
        )
        self.revision = revision
    }

    /// Keep the current task evidence in place while its data revision or live
    /// minute advances. A different task, range, or calendar interval must load
    /// before it replaces the visible snapshot.
    func canRemainVisible(whileLoading request: TaskAnalyticsSnapshotRequest) -> Bool {
        taskID == request.taskID
            && range == request.range
            && evaluationKey.interval == request.evaluationKey.interval
    }
}
