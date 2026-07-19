import SwiftUI

struct AnalyticsDetailSection<Content: View>: View {
    let title: String
    let subtitle: String?
    let headerIdentifier: String?
    @ViewBuilder var content: Content

    init(
        title: String,
        subtitle: String?,
        headerIdentifier: String? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.headerIdentifier = headerIdentifier
        self.content = content()
    }

    var body: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 6)
        } header: {
            if let headerIdentifier {
                Text(title)
                    .accessibilityIdentifier(headerIdentifier)
            } else {
                Text(title)
            }
        }
    }
}

struct AnalyticsMetricList: View {
    let overview: AnalyticsOverview
    let comparison: AnalyticsComparison
    let rhythm: AnalyticsRhythm

    var body: some View {
        VStack(spacing: 0) {
            AnalyticsMetricListRow(
                title: AppStrings.wallTime,
                value: DurationFormatter.compact(overview.wallSeconds),
                footnote: String(
                    format: AppStrings.localized(deltaFootnoteFormatKey),
                    deltaText(comparison.wallDeltaSeconds)
                ),
                systemImage: "clock",
                tint: AppColors.wallTime,
                identifier: "analytics.metric.wall"
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.grossTime,
                value: DurationFormatter.compact(overview.grossSeconds),
                footnote: String(
                    format: AppStrings.localized(deltaFootnoteFormatKey),
                    deltaText(comparison.grossDeltaSeconds)
                ),
                systemImage: "sum",
                tint: AppColors.grossTime,
                identifier: "analytics.metric.gross"
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.overlap"),
                value: DurationFormatter.compact(overview.overlapSeconds),
                footnote: AppStrings.localized("analytics.overlap.footnote"),
                systemImage: "rectangle.2.swap",
                tint: .orange,
                identifier: "analytics.metric.overlap"
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.pomodoros"),
                value: "\(overview.pomodoroCount)",
                footnote: AppStrings.localized("analytics.pomodoros.footnote"),
                systemImage: "timer",
                tint: .red,
                identifier: "analytics.metric.pomodoros"
            )
            Divider()
            AnalyticsMetricListRow(
                title: AppStrings.localized("analytics.metric.dailyPace"),
                value: DurationFormatter.compact(rhythm.dailyAverageGrossSeconds),
                footnote: String(
                    format: AppStrings.localized("analytics.metric.activeDaysFormat"),
                    rhythm.activeDayCount
                ),
                systemImage: "calendar",
                tint: .purple,
                identifier: "analytics.metric.dailyPace"
            )
        }
    }

    private var deltaFootnoteFormatKey: String {
        switch comparison.window.basis {
        case .matchedProgress:
            return "analytics.metric.deltaMatchedFootnoteFormat"
        case .completePeriods:
            return "analytics.metric.deltaCompleteFootnoteFormat"
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let title: String
    let value: String
    let footnote: String
    let systemImage: String
    let tint: Color
    let identifier: String

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    metricIdentity
                    metricValue
                }
            } else {
                HStack(spacing: 12) {
                    metricIdentity
                    Spacer(minLength: 8)
                    metricValue
                }
            }
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }

    private var metricIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: systemImage, tint: tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var metricValue: some View {
        Text(value)
            .font(.title3.weight(.semibold).monospacedDigit())
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.72)
    }
}
