import SwiftUI

/// Today's gross/wall totals, as a grouped list section (compact) or a
/// titled card (regular canvas).
struct HomeOverviewSection: View {
    let container: HomeSectionContainer
    let metrics: TodayMetricsSnapshot
    let showsWallTime: Bool

    var body: some View {
        switch container {
        case .listSection:
            Section {
                summary
            } header: {
                header
                    .textCase(nil)
            }
        case .card:
            VStack(alignment: .leading, spacing: 10) {
                header
                summary
                    .padding(14)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: .infinity)
                    .appCard(padding: 0)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("home.overview.card")
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private var header: some View {
        HomeSectionHeader(
            container: container,
            title: AppStrings.localized("home.overview.title"),
            accessibilityIdentifier: "home.overview.header"
        ) {
            HomeSectionInformationButton.overview(
                showsWallTime: showsWallTime
            )
        }
    }

    private var summary: some View {
        VStack(spacing: 12) {
            HomeSummaryMetric(
                title: AppStrings.grossTime,
                seconds: metrics.grossSeconds,
                systemImage: "square.stack.3d.up",
                tint: AppColors.grossTime
            )

            if showsWallTime {
                Divider()
                HomeSummaryMetric(
                    title: AppStrings.wallTime,
                    seconds: metrics.wallSeconds,
                    systemImage: "timeline.selection",
                    tint: AppColors.wallTime
                )
            }
        }
        .accessibilityIdentifier("home.overview")
    }
}

private struct HomeSummaryMetric: View {
    let title: String
    let seconds: Int
    let systemImage: String
    let tint: Color
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Label {
                        Text(title)
                            .font(.headline)
                    } icon: {
                        AppIconTile(systemImage: systemImage, tint: tint, size: AppLayout.rowIconSize)
                    }
                    value
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(spacing: 12) {
                    AppIconTile(systemImage: systemImage, tint: tint, size: AppLayout.rowIconSize)
                    Text(title)
                    Spacer(minLength: 12)
                    value
                        .font(.headline.monospacedDigit())
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var value: some View {
        AnimatedNumberText(text: DurationFormatter.compact(seconds), value: seconds)
    }
}
