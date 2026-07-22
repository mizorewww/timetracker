import SwiftUI

struct HomeWeeklyGrossTimeChart: View {
    let snapshot: WeeklyGrossTimeSnapshot
    let chartHeight: CGFloat
    let emptyHeight: CGFloat
    let calendar: Calendar

    var body: some View {
        if snapshot.hasTrackedTime {
            VStack(spacing: 0) {
                DailyTimeSeriesChart(
                    points: snapshot.daily,
                    mode: .grossBars,
                    accessibilityTitle: AppStrings.localized(
                        "home.weeklyGross.title"
                    ),
                    accessibilitySummary: DurationFormatter.spoken(
                        snapshot.totalGrossSeconds
                    ),
                    dateDomain: chartDomain
                )
            }
            .frame(maxWidth: 720)
            .frame(height: chartHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
        } else {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(.app("home.weeklyGross.empty"))
                        .font(.subheadline.weight(.medium))
                    Text(.app("home.weeklyGross.emptyDescription"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, minHeight: emptyHeight)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("home.weeklyGross.empty")
        }
    }

    private var chartDomain: ClosedRange<Date>? {
        guard let domainStart = calendar.date(
            byAdding: .hour,
            value: -12,
            to: snapshot.interval.start
        ), let finalDay = calendar.date(
            byAdding: .day,
            value: -1,
            to: snapshot.interval.end
        ), let domainEnd = calendar.date(
            byAdding: .hour,
            value: 12,
            to: finalDay
        ), domainEnd > domainStart else {
            return nil
        }
        return domainStart...domainEnd
    }
}
