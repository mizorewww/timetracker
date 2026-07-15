import SwiftUI

struct AnalyticsPeriodSection: View {
    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    var body: some View {
        Section {
            AnalyticsPeriodFilter(
                range: $range,
                referenceDate: $referenceDate,
                liveNow: liveNow
            )
        }
    }
}

private struct AnalyticsPeriodFilter: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                rangePicker
                    .fixedSize(horizontal: true, vertical: false)
                AnalyticsPeriodNavigator(
                    range: range,
                    referenceDate: $referenceDate,
                    liveNow: liveNow
                )
                .fixedSize(horizontal: true, vertical: false)
            }

            VStack(alignment: .leading, spacing: 8) {
                rangePicker
                AnalyticsPeriodNavigator(
                    range: range,
                    referenceDate: $referenceDate,
                    liveNow: liveNow
                )
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(AppStrings.localized("analytics.controls.title"))
        .accessibilityValue(
            AnalyticsPeriodText.title(
                for: range,
                date: referenceDate,
                liveNow: liveNow
            )
        )
        .accessibilityIdentifier("analytics.periodFilter")
    }

    @ViewBuilder
    private var rangePicker: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                Picker(AppStrings.localized("analytics.range"), selection: $range) {
                    rangeOptions
                }
                .pickerStyle(.menu)
                .labelsHidden()
            } else {
                Picker(AppStrings.localized("analytics.range"), selection: $range) {
                    rangeOptions
                }
                .pickerStyle(.segmented)
            }
        }
        .frame(minHeight: 44)
        .accessibilityIdentifier("analytics.range")
    }

    @ViewBuilder
    private var rangeOptions: some View {
        ForEach(AnalyticsRange.allCases) { range in
            Text(range.displayName).tag(range)
        }
    }
}
