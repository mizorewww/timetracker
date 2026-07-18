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
