import SwiftUI

struct AnalyticsPeriodSection: View {
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
        .accessibilityIdentifier("analytics.periodControl")
    }

    private func movePeriod(by value: Int) {
        let next = range.date(byAdding: value, to: referenceDate) ?? referenceDate
        referenceDate = min(next, liveNow)
    }
}

struct AnalyticsDetailSection<Content: View>: View {
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
