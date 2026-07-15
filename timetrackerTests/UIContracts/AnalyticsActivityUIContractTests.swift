import Foundation
import Testing

struct AnalyticsActivityUIContractTests {
    @Test
    func hourlyActivityUsesOneSharedScaleAndAConservedStackHeight() throws {
        let activity = try sourceText(
            "timetracker/Features/Analytics/Sections/AnalyticsActivityViews.swift"
        )
        let bars = try sourceText(
            "timetracker/Features/Analytics/Sections/AnalyticsActivityBarViews.swift"
        )
        let english = try sourceText("timetracker/en.lproj/Localizable.strings")
        let simplifiedChinese = try sourceText("timetracker/zh-Hans.lproj/Localizable.strings")
        let traditionalChinese = try sourceText("timetracker/zh-Hant.lproj/Localizable.strings")

        #expect(activity.contains("HourActivityScale(hourTotals: activity.map(\\.totalSeconds))"))
        #expect(activity.contains("@ScaledMetric(relativeTo: .body) private var chartHeight"))
        #expect(activity.contains("dynamicTypeSize.isAccessibilitySize ? [0, 12, 24]"))
        #expect(activity.contains("if dynamicTypeSize.isAccessibilitySize"))
        #expect(activity.contains("[GridItem(.flexible(), alignment: .leading)]"))
        #expect(activity.contains("LazyVGrid(columns: legendColumns"))
        #expect(activity.contains("ViewThatFits(in: .horizontal)"))
        #expect(activity.contains("lhs.taskID.uuidString < rhs.taskID.uuidString"))
        #expect(activity.contains("analytics.hourDistribution.content"))
        #expect(activity.contains(".accessibilityHidden(true)"))
        #expect(activity.contains("scale: scale"))
        #expect(bars.contains("scale.height("))
        #expect(bars.contains("availableHeight: Double(max(0, targetHeight))"))
        #expect(bars.contains("minSliceHeight: 0"))
        #expect(bars.contains("maxItems:") == false)
        #expect(bars.contains("VStack(spacing: 0)"))
        #expect(bars.contains(".frame(height: targetHeight, alignment: .bottom)"))
        #expect(bars.contains(".compositingGroup()"))
        #expect(bars.contains(".accessibilityValue(accessibilityValue)"))
        #expect(english.contains("Bar height compares tracked time by hour"))
        #expect(simplifiedChinese.contains("柱高对比每小时的跟踪时长"))
        #expect(traditionalChinese.contains("柱高比較每小時的追蹤時長"))
    }
}
