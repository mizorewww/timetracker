import Foundation
import SwiftUI
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreArchitectureBehaviorTests {
    @Test @MainActor
    func rootLayoutPolicyChoosesTheShellFromWidthNotTheDevice() {
        let breakpoint = RootLayoutPolicy.regularShellMinimumWidth
        #expect(breakpoint == WidthLayoutPolicy.narrowMaximumWidth)

        // A compact size class always wins, whatever the width says. This is
        // what keeps an ordinary iPhone in landscape on the tab shell.
        #expect(
            RootLayoutPolicy(measuredWidth: 1024, horizontalSizeClass: .compact)
                .shell == .compact
        )

        // macOS reports `.regular` at every width, so width alone decides — a
        // narrow window gets the same shell an iPhone gets.
        #expect(
            RootLayoutPolicy(measuredWidth: breakpoint - 1, horizontalSizeClass: .regular)
                .shell == .compact
        )
        #expect(
            RootLayoutPolicy(measuredWidth: breakpoint, horizontalSizeClass: .regular)
                .shell == .regular
        )
        #expect(
            RootLayoutPolicy(measuredWidth: breakpoint - 0.1, horizontalSizeClass: .regular)
                .shell == .compact
        )
        #expect(
            RootLayoutPolicy(measuredWidth: breakpoint + 0.1, horizontalSizeClass: .regular)
                .shell == .regular
        )

        // An iPad at half width is below the breakpoint and must not try to
        // keep both split-view columns.
        #expect(
            RootLayoutPolicy(measuredWidth: 507, horizontalSizeClass: nil)
                .shell == .compact
        )
        #expect(
            RootLayoutPolicy(measuredWidth: 1024, horizontalSizeClass: nil)
                .shell == .regular
        )

        // Before the first measurement the size class is the only signal, so
        // the shell must not flash the wrong way for one frame.
        #expect(
            RootLayoutPolicy(measuredWidth: nil, horizontalSizeClass: .regular)
                .shell == .regular
        )
        #expect(
            RootLayoutPolicy(measuredWidth: nil, horizontalSizeClass: .compact)
                .shell == .compact
        )
    }

    @Test
    func enumDisplayTextUsesLocalizationKeys() {
        #expect(AnalyticsRange.today.displayName == AppStrings.localized("analytics.range.day"))
        #expect(TimeSessionSource.importCalendar.displayName == AppStrings.localized("source.calendar"))
    }

    @Test @MainActor
    func layoutPoliciesCentralizeResponsiveChoices() {
        #expect(HomeLayoutPolicy(width: 600).isCompact)
        #expect(HomeLayoutPolicy(width: 900).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1022).contentWidth == 966)
        #expect(HomeLayoutPolicy(width: 1022).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1055).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1056).contentWidth == 1000)
        #expect(HomeLayoutPolicy(width: 1056).usesTwoColumnContent)
        #expect(HomeLayoutPolicy(width: 1236).contentWidth == 1180)
        #expect(HomeLayoutPolicy(width: 1400).contentWidth == 1180)
        #expect(HomeLayoutPolicy(width: 1100).contentMaxWidth == 1180)
        #expect(HomeLayoutPolicy(width: 1100).supportingColumnWidth == 360)
        let narrowToday = HomeLayoutPolicy(width: 799)
        let wideToday = HomeLayoutPolicy(width: 800)
        let twoColumnToday = HomeLayoutPolicy(width: 1056)
        let widestToday = HomeLayoutPolicy(width: 1400)
        #expect(
            narrowToday.usesSideBySideCurrentState(prefersSingleColumn: false) ==
                false
        )
        #expect(wideToday.usesSideBySideCurrentState(prefersSingleColumn: false))
        #expect(
            wideToday.usesSideBySideCurrentState(prefersSingleColumn: true) ==
                false
        )
        #expect(wideToday.currentStatePrimaryColumnWidth == 442)
        #expect(wideToday.currentStateOverviewColumnWidth == 280)
        #expect(
            wideToday.currentStatePrimaryColumnWidth +
                wideToday.contentSpacing +
                wideToday.currentStateOverviewColumnWidth ==
                wideToday.contentWidth
        )
        #expect(widestToday.currentStatePrimaryColumnWidth == 620)
        #expect(widestToday.currentStateOverviewColumnWidth == 538)
        #expect(twoColumnToday.wideVisualizationColumnWidth == 678)
        #expect(twoColumnToday.wideQuickStartColumnWidth == 300)
        #expect(
            twoColumnToday.wideVisualizationColumnWidth +
                twoColumnToday.contentSpacing +
                twoColumnToday.wideQuickStartColumnWidth ==
                twoColumnToday.contentWidth
        )
        #expect(widestToday.wideVisualizationColumnWidth == 748)
        #expect(widestToday.wideQuickStartColumnWidth == 410)
        // One split preset for every platform that shows the split shell. Its
        // detail minimum must stay under the shell breakpoint, otherwise there
        // would be a band of widths the split view cannot satisfy and the
        // compact shell has not taken over yet.
        #expect(SplitColumnLayoutPolicy.standard.sidebar == ColumnWidth(min: 220, ideal: 250, max: 300))
        #expect(SplitColumnLayoutPolicy.standard.detail == ColumnWidth(min: 420, ideal: 760, max: nil))
        #expect(
            SplitColumnLayoutPolicy.standard.sidebar.min +
                SplitColumnLayoutPolicy.standard.detail.min <=
                RootLayoutPolicy.regularShellMinimumWidth
        )
        #expect(PomodoroLayoutPolicy(shell: .compact).setupCardPadding == 18)
        #expect(PomodoroLayoutPolicy(shell: .compact).setupSectionSpacing == 20)
        #expect(PomodoroLayoutPolicy(shell: .regular).setupCardPadding == 24)
        #expect(DailyTimeSeriesChartLayoutPolicy(availableWidth: 390).maximumLabelCount == 5)
        #expect(DailyTimeSeriesChartLayoutPolicy(availableWidth: 390).trailingAxisClearance == 8)
        #expect(DailyTimeSeriesChartLayoutPolicy(availableWidth: 680).maximumLabelCount == 8)
        #expect(DailyTimeSeriesChartLayoutPolicy(availableWidth: 680).trailingAxisClearance == 48)
        #expect(PomodoroPageLayoutPolicy(viewportWidth: 390, prefersSingleColumn: false).verticalPadding == 16)
        #expect(PomodoroPageLayoutPolicy(viewportWidth: 900, prefersSingleColumn: false).verticalPadding == 24)
    }

    @Test @MainActor
    func homeVisualizationsFillNarrowContentAndCapReadableWidth() {
        let widths: [CGFloat] = [0, 600, 900, 1400]
        let policies = widths.map(HomeLayoutPolicy.init(width:))

        #expect(policies.map(\.visualizationSectionWidth) == [0, 564, 748, 748])
        #expect(
            policies.allSatisfy {
                $0.visualizationSectionWidth >= 0 &&
                    $0.visualizationSectionWidth <= $0.contentWidth
            }
        )
    }
}
