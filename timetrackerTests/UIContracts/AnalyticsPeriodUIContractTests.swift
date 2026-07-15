import Foundation
import Testing

@Suite(.serialized)
struct AnalyticsPeriodUIContractTests {
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

        #expect(controls.contains("DatePicker("))
        #expect(controls.contains("analytics.period.previous"))
        #expect(controls.contains("analytics.period.next"))
        #expect(controls.contains("analytics.period.today"))
        #expect(
            controls.components(
                separatedBy: ".frame(minWidth: 44, minHeight: 44)"
            ).count - 1 >= 2
        )
        #expect(controls.components(separatedBy: ".frame(minHeight: 44)").count - 1 >= 2)
        #expect(controls.contains("AnalyticsPeriodNavigation.date("))
        #expect(root.contains("@State private var monthNavigationAnchor"))
        #expect(root.contains("monthNavigationAnchor: $monthNavigationAnchor"))
        #expect(detail.contains("@Binding var monthNavigationAnchor"))
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
    }
}
