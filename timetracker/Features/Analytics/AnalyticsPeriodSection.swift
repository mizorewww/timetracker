import SwiftUI

struct AnalyticsPeriodSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @Binding var range: AnalyticsRange
    @Binding var referenceDate: Date
    let liveNow: Date

    private var isCurrentPeriod: Bool {
        range.isCurrentPeriod(referenceDate, liveNow: liveNow)
    }

    var body: some View {
        Section {
            rangePicker
            datePicker
            periodControls
        } header: {
            Text(AppStrings.localized("analytics.controls.title"))
        } footer: {
            Text(AnalyticsPeriodText.title(for: range, date: referenceDate))
        }
    }

    @ViewBuilder
    private var rangePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Picker(AppStrings.localized("analytics.range"), selection: $range) {
                rangeOptions
            }
            .pickerStyle(.menu)
        } else {
            Picker(AppStrings.localized("analytics.range"), selection: $range) {
                rangeOptions
            }
            .pickerStyle(.segmented)
            .padding(.vertical, 4)
        }
    }

    @ViewBuilder
    private var rangeOptions: some View {
        ForEach(AnalyticsRange.allCases) { range in
            Text(range.displayName).tag(range)
        }
    }

    @ViewBuilder
    private var datePicker: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 8) {
                Text(AppStrings.localized("analytics.period.select"))
                DatePicker(
                    AppStrings.localized("analytics.period.select"),
                    selection: $referenceDate,
                    in: ...liveNow,
                    displayedComponents: .date
                )
                .labelsHidden()
            }
        } else {
            DatePicker(
                AppStrings.localized("analytics.period.select"),
                selection: $referenceDate,
                in: ...liveNow,
                displayedComponents: .date
            )
        }
    }

    private var periodControls: some View {
        HStack {
            periodButton(
                label: AppStrings.localized("analytics.period.previous"),
                systemImage: "chevron.left",
                disabled: false
            ) {
                movePeriod(by: -1)
            }

            Spacer()

            periodButton(
                label: AppStrings.localized("analytics.period.current"),
                systemImage: "calendar",
                disabled: isCurrentPeriod
            ) {
                referenceDate = liveNow
            }

            Spacer()

            periodButton(
                label: AppStrings.localized("analytics.period.next"),
                systemImage: "chevron.right",
                disabled: isCurrentPeriod
            ) {
                movePeriod(by: 1)
            }
        }
        .buttonStyle(.borderless)
    }

    private func periodButton(
        label: String,
        systemImage: String,
        disabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .frame(width: 44, height: 44)
                .contentShape(.rect)
        }
        .disabled(disabled)
        .accessibilityLabel(label)
        .help(label)
    }

    private func movePeriod(by value: Int) {
        let next = range.date(byAdding: value, to: referenceDate) ?? referenceDate
        referenceDate = min(next, liveNow)
    }
}
