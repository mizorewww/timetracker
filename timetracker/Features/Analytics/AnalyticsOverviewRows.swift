import SwiftUI

struct AnalyticsHomeSummaryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: AnalyticsSnapshot

    var body: some View {
        Group {
            if snapshot.overview.grossSeconds > 0 || snapshot.overview.pomodoroCount > 0 {
                VStack(alignment: .leading, spacing: 14) {
                    headlineMetrics

                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            summaryMetadata
                        }
                    } else {
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 14) {
                                summaryMetadata
                            }
                            VStack(alignment: .leading, spacing: 8) {
                                summaryMetadata
                            }
                        }
                    }
                }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    Label(
                        AppStrings.localized("analytics.summary.emptyTitle"),
                        systemImage: "clock"
                    )
                    .font(.headline)

                    Text(AppStrings.localized("analytics.summary.emptyMessage"))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("analytics.summary")
    }

    @ViewBuilder
    private var headlineMetrics: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 14) {
                grossMetric
                wallMetric
            }
        } else {
            HStack(alignment: .firstTextBaseline) {
                grossMetric
                Spacer(minLength: 12)
                wallMetric
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    private var grossMetric: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(DurationFormatter.compact(snapshot.overview.grossSeconds))
                .font(.largeTitle.weight(.semibold).monospacedDigit())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.72)
            Text(AppStrings.localized("analytics.summary.grossLabel"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var wallMetric: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 3) {
            Text(DurationFormatter.compact(snapshot.overview.wallSeconds))
                .font(.title3.weight(.semibold).monospacedDigit())
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.72)
            Text(AppStrings.localized("analytics.summary.wallLabel"))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var summaryMetadata: some View {
        AnalyticsSummaryMiniMetric(
            value: "\(snapshot.overview.pomodoroCount)",
            label: AppStrings.localized("analytics.summary.focusRuns")
        )
        AnalyticsSummaryMiniMetric(
            value: DurationFormatter.compact(snapshot.rhythm.dailyAverageGrossSeconds),
            label: AppStrings.localized("analytics.summary.dailyAverage")
        )
        AnalyticsSummaryMiniMetric(
            value: "\(Int((snapshot.quality.overlapRatio * 100).rounded()))%",
            label: AppStrings.localized("analytics.quality.overlapRatio")
        )
    }
}

private struct AnalyticsSummaryMiniMetric: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct AnalyticsCategoryRow: View {
    let category: AnalyticsCategory
    let snapshot: AnalyticsSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: category.systemImage, tint: category.tint)

            VStack(alignment: .leading, spacing: 5) {
                Text(category.questionTitle)
                    .font(.body.weight(.medium))
                Text(category.answerPreview(from: snapshot))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(category.openLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.tint)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}
