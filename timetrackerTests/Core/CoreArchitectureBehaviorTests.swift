import Foundation
import SwiftUI
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreArchitectureBehaviorTests {
    @Test @MainActor
    func rootLayoutPolicyUsesStableInterfaceIdiom() {
        #expect(RootLayoutPolicy(interfaceIdiom: .phone).shell == .phone)
        #expect(RootLayoutPolicy(interfaceIdiom: .pad).shell == .pad)
        #expect(RootLayoutPolicy(interfaceIdiom: .unsupported).shell == .phone)

        #if os(iOS)
        #expect(RootLayoutPolicy(userInterfaceIdiom: .phone).shell == .phone)
        #expect(RootLayoutPolicy(userInterfaceIdiom: .pad).shell == .pad)
        #expect(RootLayoutPolicy(userInterfaceIdiom: .unspecified).shell == .phone)
        #endif
    }

    @Test
    func enumDisplayTextUsesLocalizationKeys() throws {
        #expect(AnalyticsRange.today.displayName == AppStrings.localized("analytics.range.day"))
        #expect(TimeSessionSource.importCalendar.displayName == AppStrings.localized("source.calendar"))
    }

    @Test @MainActor
    func layoutPoliciesCentralizeResponsiveChoices() {
        #expect(HomeLayoutPolicy(width: 600).isCompact)
        #expect(HomeLayoutPolicy(width: 900).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1_022).contentWidth == 966)
        #expect(HomeLayoutPolicy(width: 1_022).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1_055).usesTwoColumnContent == false)
        #expect(HomeLayoutPolicy(width: 1_056).contentWidth == 1_000)
        #expect(HomeLayoutPolicy(width: 1_056).usesTwoColumnContent)
        #expect(HomeLayoutPolicy(width: 1_236).contentWidth == 1_180)
        #expect(HomeLayoutPolicy(width: 1_400).contentWidth == 1_180)
        #expect(HomeLayoutPolicy(width: 1_100).contentMaxWidth == 1_180)
        #expect(HomeLayoutPolicy(width: 1_100).supportingColumnWidth == 360)
        let narrowToday = HomeLayoutPolicy(width: 799)
        let wideToday = HomeLayoutPolicy(width: 800)
        let widestToday = HomeLayoutPolicy(width: 1_400)
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
        #expect(AnalyticsLayoutPolicy(horizontalSizeClass: nil).showsPageTitleInContent)
        #expect(SplitColumnLayoutPolicy.iPad.detail == ColumnWidth(min: 480, ideal: 760, max: nil))
        #expect(SplitColumnLayoutPolicy.mac.sidebar == ColumnWidth(min: 220, ideal: 240, max: 270))
        #expect(SplitColumnLayoutPolicy.mac.detail == ColumnWidth(min: 420, ideal: 720, max: nil))
        #expect(PomodoroLayoutPolicy(horizontalSizeClass: .compact).setupCardPadding == 18)
        #expect(PomodoroLayoutPolicy(horizontalSizeClass: .compact).setupSectionSpacing == 20)
        #expect(PomodoroLayoutPolicy(horizontalSizeClass: .regular).setupCardPadding == 24)
        #expect(PomodoroPageLayoutPolicy(viewportWidth: 390, prefersSingleColumn: false).verticalPadding == 16)
        #expect(PomodoroPageLayoutPolicy(viewportWidth: 900, prefersSingleColumn: false).verticalPadding == 24)
    }
}
