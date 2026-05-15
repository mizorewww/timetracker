import SwiftUI

struct AnalyticsDecisionSummaryGrid: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("analytics.decisions.title"),
            subtitle: AppStrings.localized("analytics.decisions.subtitle")
        ) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                ForEach(snapshot.insights) { insight in
                    AnalyticsInsightCard(insight: insight)
                }
            }
        }
    }
}

private struct AnalyticsInsightCard: View {
    let insight: AnalyticsInsight

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: iconName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Text(insight.title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }

            Text(insight.value)
                .font(.title3.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(insight.body)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .appCard(padding: 14)
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

struct AnalyticsBreakdownSection: View {
    let snapshot: AnalyticsSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TaskDonutCard(
                tasks: snapshot.taskBreakdown,
                totalSeconds: max(snapshot.overview.grossSeconds, 1)
            )

            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    AnalyticsGroupBreakdownCard(
                        title: AppStrings.localized("analytics.rootUsage.title"),
                        subtitle: AppStrings.localized("analytics.rootUsage.subtitle"),
                        items: snapshot.rootBreakdown,
                        totalSeconds: max(snapshot.rootBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                    )
                    AnalyticsGroupBreakdownCard(
                        title: AppStrings.localized("analytics.categoryUsage.title"),
                        subtitle: AppStrings.localized("analytics.categoryUsage.subtitle"),
                        items: snapshot.categoryBreakdown,
                        totalSeconds: max(snapshot.categoryBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                    )
                }

                VStack(alignment: .leading, spacing: 14) {
                    AnalyticsGroupBreakdownCard(
                        title: AppStrings.localized("analytics.rootUsage.title"),
                        subtitle: AppStrings.localized("analytics.rootUsage.subtitle"),
                        items: snapshot.rootBreakdown,
                        totalSeconds: max(snapshot.rootBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                    )
                    AnalyticsGroupBreakdownCard(
                        title: AppStrings.localized("analytics.categoryUsage.title"),
                        subtitle: AppStrings.localized("analytics.categoryUsage.subtitle"),
                        items: snapshot.categoryBreakdown,
                        totalSeconds: max(snapshot.categoryBreakdown.reduce(0) { $0 + $1.grossSeconds }, 1)
                    )
                }
            }
        }
    }
}

struct AnalyticsGroupBreakdownCard: View {
    let title: String
    let subtitle: String
    let items: [AnalyticsGroupBreakdownPoint]
    let totalSeconds: Int

    private var visibleItems: [AnalyticsGroupBreakdownPoint] {
        Array(items.prefix(6))
    }

    var body: some View {
        AnalyticsChartCard(title: title, subtitle: subtitle) {
            if visibleItems.isEmpty {
                EmptyStateRow(title: AppStrings.localized("analytics.empty.rangeTaskTime"), icon: "chart.pie")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    stackedBar
                    VStack(spacing: 0) {
                        ForEach(visibleItems) { item in
                            AnalyticsGroupBreakdownRow(item: item, totalSeconds: totalSeconds)
                            if item.id != visibleItems.last?.id {
                                Divider()
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var stackedBar: some View {
        GeometryReader { proxy in
            HStack(spacing: 3) {
                ForEach(visibleItems) { item in
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .fill(Color(hex: item.colorHex) ?? .blue)
                        .frame(width: segmentWidth(for: item, totalWidth: proxy.size.width))
                }
            }
        }
        .frame(height: 16)
        .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private func segmentWidth(for item: AnalyticsGroupBreakdownPoint, totalWidth: CGFloat) -> CGFloat {
        let ratio = CGFloat(item.grossSeconds) / CGFloat(max(totalSeconds, 1))
        return max(10, totalWidth * ratio)
    }
}

private struct AnalyticsGroupBreakdownRow: View {
    let item: AnalyticsGroupBreakdownPoint
    let totalSeconds: Int

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: item.iconName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color(hex: item.colorHex) ?? .blue)
                .frame(width: 20, height: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(1)
                Text(item.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(DurationFormatter.compact(item.grossSeconds))
                    .font(.subheadline.monospacedDigit())
                Text("\(Int((Double(item.grossSeconds) / Double(max(totalSeconds, 1))) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 9)
    }
}

struct AnalyticsRhythmQualityGrid: View {
    let rhythm: AnalyticsRhythm
    let quality: AnalyticsQuality

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 14) {
                AnalyticsRhythmCard(rhythm: rhythm)
                AnalyticsQualityCard(quality: quality)
            }

            VStack(alignment: .leading, spacing: 14) {
                AnalyticsRhythmCard(rhythm: rhythm)
                AnalyticsQualityCard(quality: quality)
            }
        }
    }
}

private struct AnalyticsRhythmCard: View {
    let rhythm: AnalyticsRhythm

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("analytics.rhythm.title"),
            subtitle: AppStrings.localized("analytics.rhythm.subtitle")
        ) {
            VStack(spacing: 10) {
                InfoRow(title: AppStrings.localized("analytics.rhythm.peakHour"), value: peakHourText)
                InfoRow(title: AppStrings.localized("analytics.rhythm.activeDays"), value: "\(rhythm.activeDayCount)")
                InfoRow(title: AppStrings.localized("analytics.rhythm.longest"), value: DurationFormatter.compact(rhythm.longestContinuousSeconds))
                InfoRow(title: AppStrings.localized("analytics.rhythm.averageSegment"), value: DurationFormatter.compact(rhythm.averageSegmentSeconds))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var peakHourText: String {
        guard let peakHour = rhythm.peakHour else {
            return AppStrings.localized("analytics.none")
        }
        return String(format: AppStrings.localized("analytics.rhythm.peakHourFormat"), peakHour, DurationFormatter.compact(rhythm.peakHourSeconds))
    }
}

private struct AnalyticsQualityCard: View {
    let quality: AnalyticsQuality

    var body: some View {
        AnalyticsChartCard(
            title: AppStrings.localized("analytics.quality.title"),
            subtitle: AppStrings.localized("analytics.quality.subtitle")
        ) {
            VStack(spacing: 10) {
                InfoRow(title: AppStrings.localized("analytics.quality.overlapRatio"), value: percentText(quality.overlapRatio))
                InfoRow(title: AppStrings.localized("analytics.quality.switches"), value: "\(quality.switchCount)")
                InfoRow(title: AppStrings.localized("analytics.quality.shortSegments"), value: String(format: AppStrings.localized("analytics.quality.shortSegmentsFormat"), quality.shortSegmentCount, percentText(quality.shortSegmentRatio)))
                InfoRow(title: AppStrings.localized("analytics.quality.longest"), value: DurationFormatter.compact(quality.longestContinuousSeconds))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}
