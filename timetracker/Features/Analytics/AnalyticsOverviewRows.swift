import SwiftUI

struct AnalyticsHomeSummaryRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let snapshot: AnalyticsSnapshot

    var body: some View {
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
            Text(AppStrings.grossTime)
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
            Text(AppStrings.wallTime)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let category: AnalyticsCategory
    let snapshot: AnalyticsSnapshot

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    categoryIdentity
                    categoryValue
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    categoryIdentity
                    Spacer(minLength: 8)
                    categoryValue
                        .multilineTextAlignment(.trailing)
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var categoryIdentity: some View {
        HStack(alignment: .top, spacing: 12) {
            SettingsRowIcon(systemImage: category.systemImage, tint: category.tint)

            VStack(alignment: .leading, spacing: 3) {
                Text(category.title)
                    .font(.body)
                Text(category.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var categoryValue: some View {
        VStack(alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing, spacing: 2) {
            Text(category.value(from: snapshot))
                .font(.subheadline.weight(.semibold).monospacedDigit())
            Text(category.valueLabel(from: snapshot))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
