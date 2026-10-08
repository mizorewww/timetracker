import SwiftUI

struct AnalyticsRhythmContent: View {
    let rhythm: AnalyticsRhythm

    var body: some View {
        VStack(spacing: 10) {
            InfoRow(title: AppStrings.localized("analytics.rhythm.peakHour"), value: peakHourText)
            InfoRow(title: AppStrings.localized("analytics.rhythm.activeDays"), value: "\(rhythm.activeDayCount)")
            InfoRow(
                title: AppStrings.localized("analytics.rhythm.longest"),
                value: DurationFormatter.compact(rhythm.longestContinuousSeconds)
            )
            InfoRow(
                title: AppStrings.localized("analytics.rhythm.averageSegment"),
                value: DurationFormatter.compact(rhythm.averageSegmentSeconds)
            )
        }
    }

    private var peakHourText: String {
        guard let peakHour = rhythm.peakHour else {
            return AppStrings.localized("analytics.none")
        }
        return String(
            format: AppStrings.localized("analytics.rhythm.peakHourFormat"),
            peakHour,
            DurationFormatter.compact(rhythm.peakHourSeconds)
        )
    }
}

struct AnalyticsQualityContent: View {
    let quality: AnalyticsQuality

    var body: some View {
        VStack(spacing: 10) {
            InfoRow(
                title: AppStrings.localized("analytics.quality.overlapRatio"),
                value: percentText(quality.overlapRatio)
            )
            InfoRow(title: AppStrings.localized("analytics.quality.switches"), value: "\(quality.switchCount)")
            InfoRow(
                title: AppStrings.localized("analytics.quality.shortSegments"),
                value: String(
                    format: AppStrings.localized("analytics.quality.shortSegmentsFormat"),
                    quality.shortSegmentCount,
                    percentText(quality.shortSegmentRatio)
                )
            )
        }
    }

    private func percentText(_ value: Double) -> String {
        "\(Int((value * 100).rounded()))%"
    }
}

private struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleText
                    .frame(minWidth: 54, maxWidth: 112, alignment: .leading)
                Spacer(minLength: 8)
                valueText
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleText
                valueText
            }
        }
        .font(rowFont)
        .accessibilityElement(children: .combine)
    }

    private var rowFont: Font {
        .body
    }

    private var titleText: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
