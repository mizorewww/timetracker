import Foundation
import Testing

@Suite(.serialized)
struct AnalyticsPeriodUIContractTests {
    @Test
    func focusRoundEvidenceAndForecastsRespectTheSelectedPeriod() throws {
        let detail = try sourceText(
            "timetracker/Features/Analytics/AnalyticsCategoryDetailContent.swift"
        )
        let focusRounds = try sourceText(
            "timetracker/Features/Analytics/Sections/AnalyticsFocusRoundViews.swift"
        )
        let snapshot = try sourceText(
            "timetracker/Stores/Domains/AnalyticsSnapshotModels.swift"
        )
        let analyticsStore = try sourceText(
            "timetracker/Stores/Domains/AnalyticsStore+Breakdowns.swift"
        )
        let analyticsCategory = try sourceText(
            "timetracker/Features/Analytics/AnalyticsCategory.swift"
        )
        let analyticsSummary = try sourceText(
            "timetracker/Features/Analytics/AnalyticsOverviewRows.swift"
        )
        let analyticsReadModels = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+AnalyticsReadModels.swift"
        )
        let analyticsFacade = try [
            "timetracker/Stores/Facade/TimeTrackerStore+Analytics.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+AnalyticsLoading.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+PomodoroReadModels.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let english = try sourceText("timetracker/en.lproj/Localizable.strings")
        let simplifiedChinese = try sourceText("timetracker/zh-Hans.lproj/Localizable.strings")
        let traditionalChinese = try sourceText("timetracker/zh-Hant.lproj/Localizable.strings")

        #expect(snapshot.contains("let completedFocusRoundSegmentIDs: [UUID]"))
        #expect(detail.contains("segmentIDs: snapshot.completedFocusRoundSegmentIDs"))
        #expect(focusRounds.contains("TimelineRow(store: store, segment: segment)"))
        #expect(detail.contains("PomodoroLedgerContent(store: store)") == false)
        #expect(focusRounds.contains("private static let maximumRenderedRoundCount = 20"))
        #expect(focusRounds.contains("analytics.focusRounds.showingFormat"))
        #expect(focusRounds.contains(".accessibilityIdentifier(\"analytics.focusRounds.summary\")"))
        #expect(focusRounds.contains("analytics.focusRounds.content") == false)
        #expect(detail.contains("if range.isCurrentPeriod(referenceDate, liveNow: liveNow)"))

        #expect(analyticsStore.contains("endedAt >= period.start"))
        #expect(analyticsStore.contains("endedAt < period.end"))
        #expect(analyticsStore.contains("endedAt <= cutoff"))
        #expect(analyticsStore.contains("endedAt > segment.startedAt"))
        #expect(analyticsStore.contains("cancelledPomodoroSessionIDs.contains(segment.sessionID) == false"))
        #expect(analyticsCategory.contains("self == .pomodoro && snapshot.overview.pomodoroCount > 0"))
        #expect(
            analyticsSummary.contains(
                "snapshot.overview.grossSeconds > 0 || snapshot.overview.pomodoroCount > 0"
            )
        )
        #expect(analyticsFacade.contains("cancelledPomodoroSessionIDs: cancelledPomodoroSessionIDs"))
        #expect(analyticsFacade.contains("run.state == .cancelled"))
        #expect(analyticsFacade.contains("run.deletedAt == nil"))

        let indexedLookup = try #require(
            analyticsReadModels.range(of: "if ledgerDomainStore.hasIndexedSegmentHistory")
        )
        let fullHistoryFallback = try #require(
            analyticsReadModels.range(of: "let fallbackByID = allSegments")
        )
        #expect(indexedLookup.lowerBound < fullHistoryFallback.lowerBound)
        #expect(
            analyticsReadModels[indexedLookup.lowerBound..<fullHistoryFallback.lowerBound]
                .contains("return segmentIDs.compactMap")
        )

        #expect(english.contains("\"analytics.category.pomodoro.title\" = \"Focus Rounds\";"))
        #expect(
            english.contains(
                "\"analytics.focusRounds.showingFormat\" = \"Showing the latest %d of %d completed focus rounds in this range.\";"
            )
        )
        #expect(
            english.contains(
                "\"analytics.focusRounds.showingSingularFormat\" = \"Showing the latest %d of %d completed focus round in this range.\";"
            )
        )
        #expect(english.contains("\"analytics.forecasts.title\" = \"Current Task Forecasts\";"))
        #expect(simplifiedChinese.contains("\"analytics.category.pomodoro.title\" = \"专注轮次\";"))
        #expect(traditionalChinese.contains("\"analytics.category.pomodoro.title\" = \"專注輪次\";"))
    }

    @Test
    func analyticsUsesOneAdaptiveNativeFilterRowWithoutRedundantVisibleLabels() throws {
        let section = try sourceText("timetracker/Features/Analytics/AnalyticsPeriodSection.swift")
        let controls = try sourceText("timetracker/Features/Analytics/AnalyticsPeriodSelectionViews.swift")
        let root = try sourceText("timetracker/Features/Analytics/AnalyticsViews.swift")
        let detail = try sourceText("timetracker/Features/Analytics/AnalyticsCategoryDetailView.swift")

        #expect(section.contains("Section {\n            AnalyticsPeriodFilter("))
        #expect(section.contains("} header:") == false)
        #expect(section.contains("} footer:") == false)
        #expect(section.contains("ViewThatFits(in: .horizontal)"))
        #expect(section.contains(".pickerStyle(.segmented)"))
        #expect(section.contains(".pickerStyle(.menu)"))
        #expect(section.contains(".labelsHidden()"))
        #expect(section.contains(".frame(minHeight: 44)"))
        #expect(section.contains("analytics.periodFilter"))
        #expect(section.contains("let isRefreshing: Bool"))
        #expect(section.contains("refreshIndicator"))

        #expect(controls.contains("DatePicker("))
        #expect(controls.contains("analytics.period.previous"))
        #expect(controls.contains("analytics.period.next"))
        #expect(controls.contains("analytics.period.today"))
        #expect(controls.contains("if isCurrentPeriod == false {\n            todayButton\n        }"))
        #expect(!controls.contains("todayButton\n        .disabled(isCurrentPeriod)"))
        #expect(
            controls.components(
                separatedBy: ".frame(minWidth: 44, minHeight: 44)"
            ).count - 1 >= 2
        )
        #expect(controls.components(separatedBy: ".frame(minHeight: 44)").count - 1 >= 2)
        #expect(controls.contains("AnalyticsPeriodNavigation.date("))
        #expect(root.contains("@State private var monthNavigationAnchor"))
        #expect(root.contains("canKeepDisplayingSnapshot"))
        #expect(root.contains("isRefreshing: loadedRequest != request"))
        #expect(root.contains("monthNavigationAnchor: $monthNavigationAnchor"))
        #expect(detail.contains("@Binding var monthNavigationAnchor"))
        #expect(detail.contains("canKeepDisplayingSnapshot"))
        #expect(detail.contains("monthNavigationAnchor: $monthNavigationAnchor"))
        #expect(section.contains("@Binding var monthNavigationAnchor"))
        #expect(controls.contains("monthNavigationAnchor = nil"))
    }

    @Test
    func analyticsPeriodActionsAndSummaryExposeStableAccessibilityIdentifiers() throws {
        let controls = try sourceText("timetracker/Features/Analytics/AnalyticsPeriodSelectionViews.swift")
        let summary = try sourceText("timetracker/Features/Analytics/AnalyticsOverviewRows.swift")
        let english = try sourceText("timetracker/en.lproj/Localizable.strings")

        for identifier in [
            "analytics.period.date",
            "analytics.period.previous",
            "analytics.period.next",
            "analytics.period.today"
        ] {
            #expect(controls.contains("\"" + identifier + "\""))
        }
        #expect(!controls.contains(".accessibilityIdentifier(\"analytics.periodControl\")"))
        #expect(controls.contains("analytics.period.returnToToday"))
        #expect(summary.contains(".accessibilityIdentifier(\"analytics.summary\")"))
        #expect(english.contains("\"analytics.period.returnToToday\" = \"Go to Today\";"))
        #expect(english.contains("\"analytics.range.day\" = \"Day\";"))
        #expect(!english.contains("\"analytics.range.today\""))
    }
}
