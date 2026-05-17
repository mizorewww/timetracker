import Combine
import SwiftUI

struct AnalyticsView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var range: AnalyticsRange = .today
    @State private var referenceDate = Date()
    @State private var now = Date()
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    private let analyticsRefreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    private var isCompactPhone: Bool {
        #if os(iOS)
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
        #else
        false
        #endif
    }

    var body: some View {
        let snapshotDate = range.effectiveSnapshotDate(referenceDate: referenceDate, liveNow: now)
        let snapshot = store.analyticsSnapshot(for: range, now: snapshotDate)
        AnalyticsContent(
            store: store,
            snapshot: snapshot,
            range: $range,
            referenceDate: $referenceDate,
            now: now,
            isCompactPhone: isCompactPhone
        )
        .navigationTitle(AppStrings.analytics)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .phoneRootChrome(destination: .analytics, enabled: isCompactPhone)
        #endif
        .background(AppColors.background)
        .onReceive(analyticsRefreshTimer) { date in
            now = date
            if referenceDate > date {
                referenceDate = date
            }
        }
    }
}

private struct AnalyticsContent: View {
    @ObservedObject var store: TimeTrackerStore
    let snapshot: AnalyticsSnapshot
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let now: Date
    let isCompactPhone: Bool

    var body: some View {
        List {
            #if os(iOS)
            if isCompactPhone {
                PhoneLargePageHeader(destination: .analytics)
                    .listRowInsets(PhoneRootChromeMetrics.groupedHeaderRowInsets)
                    .listRowBackground(Color.clear)
            }
            #endif

            Section {
                AnalyticsHomeSummaryRow(snapshot: snapshot)
            } header: {
                Text(AppStrings.localized("analytics.summary.title"))
            } footer: {
                Text(String(format: AppStrings.localized("analytics.summary.periodFootnote"), AnalyticsPeriodText.title(for: range, date: referenceDate)))
            }

            Section {
                ForEach(AnalyticsCategory.allCases) { category in
                    NavigationLink {
                        AnalyticsCategoryDetailView(
                            store: store,
                            category: category,
                            range: $range,
                            referenceDate: $referenceDate,
                            now: now
                        )
                        #if os(iOS)
                        .phoneSecondaryDestination(.analytics)
                        #endif
                    } label: {
                        AnalyticsCategoryRow(category: category, snapshot: snapshot)
                    }
                }
            } header: {
                Text(AppStrings.localized("analytics.categories.title"))
            } footer: {
                Text(AppStrings.localized("analytics.categories.footer"))
            }

            #if os(iOS)
            if isCompactPhone {
                PhoneRootListBottomClearanceRow()
            }
            #endif
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        .phoneRootScrollMargins(enabled: isCompactPhone)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        #if os(iOS)
        .phoneChromeScrollObserver(destination: .analytics, enabled: isCompactPhone)
        #endif
        .background(AppColors.background)
        .transaction { transaction in
            transaction.animation = nil
        }
    }
}

private enum AnalyticsCategory: String, CaseIterable, Identifiable {
    case overview
    case time
    case tasks
    case pomodoro
    case decisions
    case quality

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            return AppStrings.localized("analytics.category.overview.title")
        case .time:
            return AppStrings.localized("analytics.category.time.title")
        case .tasks:
            return AppStrings.localized("analytics.category.tasks.title")
        case .pomodoro:
            return AppStrings.localized("analytics.category.pomodoro.title")
        case .decisions:
            return AppStrings.localized("analytics.category.decisions.title")
        case .quality:
            return AppStrings.localized("analytics.category.quality.title")
        }
    }

    var subtitle: String {
        switch self {
        case .overview:
            return AppStrings.localized("analytics.category.overview.subtitle")
        case .time:
            return AppStrings.localized("analytics.category.time.subtitle")
        case .tasks:
            return AppStrings.localized("analytics.category.tasks.subtitle")
        case .pomodoro:
            return AppStrings.localized("analytics.category.pomodoro.subtitle")
        case .decisions:
            return AppStrings.localized("analytics.category.decisions.subtitle")
        case .quality:
            return AppStrings.localized("analytics.category.quality.subtitle")
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            return "chart.bar.doc.horizontal"
        case .time:
            return "clock"
        case .tasks:
            return "chart.pie"
        case .pomodoro:
            return "timer"
        case .decisions:
            return "lightbulb"
        case .quality:
            return "waveform.path.ecg"
        }
    }

    var tint: Color {
        switch self {
        case .overview:
            return .blue
        case .time:
            return .cyan
        case .tasks:
            return .purple
        case .pomodoro:
            return .orange
        case .decisions:
            return .yellow
        case .quality:
            return .green
        }
    }

    func value(from snapshot: AnalyticsSnapshot) -> String {
        switch self {
        case .overview:
            return DurationFormatter.compact(snapshot.overview.grossSeconds)
        case .time:
            return DurationFormatter.compact(snapshot.overview.wallSeconds)
        case .tasks:
            return String(format: AppStrings.localized("analytics.category.value.tasksFormat"), snapshot.taskBreakdown.count)
        case .pomodoro:
            return String(format: AppStrings.localized("analytics.category.value.pomodorosFormat"), snapshot.overview.pomodoroCount)
        case .decisions:
            return String(format: AppStrings.localized("analytics.category.value.insightsFormat"), snapshot.insights.count)
        case .quality:
            return "\(Int((snapshot.quality.overlapRatio * 100).rounded()))%"
        }
    }

    func valueLabel(from snapshot: AnalyticsSnapshot) -> String {
        switch self {
        case .overview:
            return AppStrings.grossTime
        case .time:
            return AppStrings.wallTime
        case .tasks:
            return AppStrings.tasks
        case .pomodoro:
            return AppStrings.localized("analytics.metric.pomodoros")
        case .decisions:
            return AppStrings.localized("analytics.category.value.insights")
        case .quality:
            return AppStrings.localized("analytics.quality.overlapRatio")
        }
    }
}

private struct AnalyticsHomeSummaryRow: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(DurationFormatter.compact(snapshot.overview.grossSeconds))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                    Text(AppStrings.grossTime)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 3) {
                    Text(DurationFormatter.compact(snapshot.overview.wallSeconds))
                        .font(.title3.weight(.semibold).monospacedDigit())
                    Text(AppStrings.wallTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 14) {
                Label("\(snapshot.overview.pomodoroCount)", systemImage: "timer")
                Label(DurationFormatter.compact(snapshot.rhythm.dailyAverageGrossSeconds), systemImage: "calendar")
                Label("\(Int((snapshot.quality.overlapRatio * 100).rounded()))%", systemImage: "rectangle.2.swap")
            }
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct AnalyticsCategoryRow: View {
    let category: AnalyticsCategory
    let snapshot: AnalyticsSnapshot

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: category.systemImage, tint: category.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.body)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(category.value(from: snapshot))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                Text(category.valueLabel(from: snapshot))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }
}

private struct AnalyticsCategoryDetailView: View {
    @ObservedObject var store: TimeTrackerStore
    let category: AnalyticsCategory
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let now: Date

    var body: some View {
        let snapshotDate = range.effectiveSnapshotDate(referenceDate: referenceDate, liveNow: now)
        let snapshot = store.analyticsSnapshot(for: range, now: snapshotDate)

        List {
            AnalyticsPeriodSection(range: $range, referenceDate: $referenceDate, liveNow: now)
            categoryContent(snapshot: snapshot)
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(AppColors.background)
        .navigationTitle(category.title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .transaction { transaction in
            transaction.animation = nil
        }
    }

    @ViewBuilder
    private func categoryContent(snapshot: AnalyticsSnapshot) -> some View {
        switch category {
        case .overview:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.summary.title"),
                subtitle: AppStrings.localized("analytics.category.overview.subtitle")
            ) {
                AnalyticsMetricList(
                    overview: snapshot.overview,
                    comparison: snapshot.comparison,
                    rhythm: snapshot.rhythm
                )
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.glossary.title"),
                subtitle: nil
            ) {
                AnalyticsGlossaryList()
            }

        case .time:
            if range == .today {
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.hourDistribution.title"),
                    subtitle: AppStrings.localized("analytics.hourDistribution.subtitle")
                ) {
                    TodayActivityContent(activity: snapshot.todayActivity)
                }

                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.timeline.title"),
                    subtitle: AppStrings.localized("analytics.timeline.subtitle")
                ) {
                    OverlappingTimelineContent(timeline: snapshot.timeline)
                }
            } else {
                AnalyticsDetailSection(
                    title: AppStrings.localized("analytics.dailyTrend.title"),
                    subtitle: AppStrings.localized("analytics.dailyTrend.subtitle")
                ) {
                    DailyTrendContent(daily: snapshot.daily)
                }
            }

        case .tasks:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.taskUsage.title"),
                subtitle: AppStrings.localized("analytics.taskUsage.subtitle")
            ) {
                TaskDonutContent(
                    tasks: snapshot.taskBreakdown,
                    totalSeconds: max(snapshot.overview.grossSeconds, 1)
                )
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.rootUsage.title"),
                subtitle: AppStrings.localized("analytics.rootUsage.subtitle")
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.rootBreakdown,
                    totalSeconds: max(snapshot.rootBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                )
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.categoryUsage.title"),
                subtitle: AppStrings.localized("analytics.categoryUsage.subtitle")
            ) {
                AnalyticsGroupBreakdownContent(
                    items: snapshot.categoryBreakdown,
                    totalSeconds: max(snapshot.categoryBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                )
            }

        case .pomodoro:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.category.pomodoro.title"),
                subtitle: AppStrings.localized("analytics.category.pomodoro.subtitle")
            ) {
                PomodoroLedgerContent(store: store)
            }

        case .decisions:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.decisions.title"),
                subtitle: AppStrings.localized("analytics.decisions.subtitle")
            ) {
                AnalyticsInsightList(insights: snapshot.insights)
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.forecasts.title"),
                subtitle: AppStrings.localized("analytics.forecasts.subtitle")
            ) {
                TaskForecastsContent(store: store)
            }

        case .quality:
            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.rhythm.title"),
                subtitle: AppStrings.localized("analytics.rhythm.subtitle")
            ) {
                AnalyticsRhythmContent(rhythm: snapshot.rhythm)
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.quality.title"),
                subtitle: AppStrings.localized("analytics.quality.subtitle")
            ) {
                AnalyticsQualityContent(quality: snapshot.quality)
            }

            AnalyticsDetailSection(
                title: AppStrings.localized("analytics.overlap.title"),
                subtitle: AppStrings.localized("analytics.overlap.subtitle")
            ) {
                AnalyticsOverlapContent(overlaps: snapshot.overlaps)
            }
        }
    }
}

private struct AnalyticsPeriodSection: View {
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    private var isCurrentPeriod: Bool {
        range.isCurrentPeriod(referenceDate, liveNow: liveNow)
    }

    var body: some View {
        Section {
            Picker(AppStrings.localized("analytics.range"), selection: $range) {
                ForEach(AnalyticsRange.allCases) { range in
                    Text(range.displayName).tag(range)
                }
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)

            DatePicker(
                AppStrings.localized("analytics.period.select"),
                selection: $referenceDate,
                in: ...liveNow,
                displayedComponents: .date
            )

            HStack {
                Button {
                    movePeriod(by: -1)
                } label: {
                    Label(AppStrings.localized("analytics.period.previous"), systemImage: "chevron.left")
                        .labelStyle(.iconOnly)
                        .frame(width: 36, height: 32)
                }
                .accessibilityLabel(AppStrings.localized("analytics.period.previous"))

                Spacer()

                Button {
                    referenceDate = liveNow
                } label: {
                    Label(AppStrings.localized("analytics.period.current"), systemImage: "calendar")
                }
                .disabled(isCurrentPeriod)

                Spacer()

                Button {
                    movePeriod(by: 1)
                } label: {
                    Label(AppStrings.localized("analytics.period.next"), systemImage: "chevron.right")
                        .labelStyle(.iconOnly)
                        .frame(width: 36, height: 32)
                }
                .disabled(isCurrentPeriod)
                .accessibilityLabel(AppStrings.localized("analytics.period.next"))
            }
            .buttonStyle(.borderless)
        } header: {
            Text(AppStrings.localized("analytics.controls.title"))
        } footer: {
            Text(AnalyticsPeriodText.title(for: range, date: referenceDate))
        }
    }

    private func movePeriod(by value: Int) {
        let next = range.date(byAdding: value, to: referenceDate) ?? referenceDate
        referenceDate = min(next, liveNow)
    }
}

private struct AnalyticsDetailSection<Content: View>: View {
    let title: String
    let subtitle: String?
    @ViewBuilder var content: Content

    var body: some View {
        Section {
            content
                .padding(.vertical, 6)
        } header: {
            Text(title)
        } footer: {
            if let subtitle, !subtitle.isEmpty {
                Text(subtitle)
            }
        }
    }
}

private struct AnalyticsMetricList: View {
    let overview: AnalyticsOverview
    let comparison: AnalyticsComparison
    let rhythm: AnalyticsRhythm

    var body: some View {
        VStack(spacing: 0) {
            AnalyticsMetricListRow(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(overview.wallSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.deltaFootnoteFormat"), deltaText(comparison.wallDeltaSeconds)),
                systemImage: "clock",
                tint: .blue
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(overview.grossSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.deltaFootnoteFormat"), deltaText(comparison.grossDeltaSeconds)),
                systemImage: "sum",
                tint: .green
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.overlap"),
                value: DurationFormatter.compact(overview.overlapSeconds),
                footnote: AppStrings.localized("analytics.overlap.footnote"),
                systemImage: "rectangle.2.swap",
                tint: .orange
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.pomodoros"),
                value: "\(overview.pomodoroCount)",
                footnote: AppStrings.localized("analytics.pomodoros.footnote"),
                systemImage: "timer",
                tint: .red
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.dailyPace"),
                value: DurationFormatter.compact(rhythm.dailyAverageGrossSeconds),
                footnote: String(format: AppStrings.localized("analytics.metric.activeDaysFormat"), rhythm.activeDayCount),
                systemImage: "calendar",
                tint: .purple
            )
        }
    }

    private func deltaText(_ seconds: Int) -> String {
        if seconds == 0 {
            return DurationFormatter.compact(0)
        }
        let prefix = seconds > 0 ? "+" : "-"
        return "\(prefix)\(DurationFormatter.compact(abs(seconds)))"
    }
}

private struct AnalyticsMetricListRow: View {
    let title: String
    let value: String
    let footnote: String
    let systemImage: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            Text(value)
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.72)
        }
        .padding(.vertical, 10)
    }
}

private struct AnalyticsGlossaryList: View {
    var body: some View {
        VStack(spacing: 0) {
            AnalyticsGlossaryRow(title: AppStrings.grossTime, bodyText: AppStrings.localized("analytics.glossary.gross"))
            Divider()
            AnalyticsGlossaryRow(title: AppStrings.wallTime, bodyText: AppStrings.localized("analytics.glossary.wall"))
            Divider()
            AnalyticsGlossaryRow(title: AppStrings.localized("analytics.metric.overlap"), bodyText: AppStrings.localized("analytics.glossary.overlap"))
        }
    }
}

private struct AnalyticsGlossaryRow: View {
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(bodyText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
    }
}

private struct AnalyticsInsightList: View {
    let insights: [AnalyticsInsight]

    var body: some View {
        VStack(spacing: 0) {
            ForEach(insights.enumerated(), id: \.element.id) { index, insight in
                AnalyticsInsightRow(insight: insight)
                if index < insights.count - 1 {
                    Divider()
                }
            }
        }
    }
}

private struct AnalyticsInsightRow: View {
    let insight: AnalyticsInsight

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: iconName, tint: tint)

            VStack(alignment: .leading, spacing: 4) {
                Text(insight.title)
                    .font(.subheadline.weight(.medium))
                Text(insight.value)
                    .font(.headline.monospacedDigit())
                Text(insight.body)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
    }

    private var iconName: String {
        switch insight.severity {
        case .positive:
            return "checkmark.seal"
        case .neutral:
            return "target"
        case .warning:
            return "exclamationmark.triangle"
        case .critical:
            return "exclamationmark.octagon"
        }
    }

    private var tint: Color {
        switch insight.severity {
        case .positive:
            return .green
        case .neutral:
            return .blue
        case .warning:
            return .orange
        case .critical:
            return .red
        }
    }
}
