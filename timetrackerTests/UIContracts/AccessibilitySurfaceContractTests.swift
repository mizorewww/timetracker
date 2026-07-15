import Foundation
import Testing

@Suite(.serialized)
struct AccessibilitySurfaceContractTests {
    @Test
    func checklistControlsExposeStateActionAndHideDecorativeSymbols() throws {
        let source = try sourceText("timetracker/SharedUI/Components/ChecklistControls.swift")

        #expect(source.contains("editor.checklist.completionControl"))
        #expect(source.contains("editor.checklist.state.completed"))
        #expect(source.contains("editor.checklist.state.incomplete"))
        #expect(source.contains("editor.checklist.action.markComplete"))
        #expect(source.contains("editor.checklist.action.markIncomplete"))
        #expect(source.contains(".accessibilityLabel(title)"))
        #expect(source.components(separatedBy: ".accessibilityHidden(true)").count - 1 >= 3)
    }

    @Test
    func timerExtensionsPreserveDynamicAccessibilityValues() throws {
        let widget = try [
            "timetrackerWidgetExtension/ActiveTimerWidgetView.swift",
            "timetrackerWidgetExtension/WidgetSupplementaryViews.swift"
        ].map(sourceText).joined(separator: "\n")
        let liveActivity = try [
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(widget.contains(".accessibilityValue(Text(timer.startedAt, style: .timer))"))
        #expect(widget.contains(".accessibilityValue(Text(generatedAt, style: .relative))"))
        #expect(liveActivity.components(separatedBy: ".accessibilityValue(Text(context.state.startedAt, style: .timer))").count - 1 == 1)
        #expect(liveActivity.contains(".accessibilityValue(Text(startedAt, style: .timer))"))
    }

    @Test
    func hourlyActivityExposesLocalizedPerHourSemantics() throws {
        let view = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsActivityViews.swift")
        let bars = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsActivityBarViews.swift")

        #expect(view.contains("AnalyticsHourLabelFormatter.string(for: hour"))
        #expect(view.contains("analytics.hourDistribution.accessibility.chart"))
        #expect(bars.contains("analytics.hourDistribution.accessibility.hour"))
        #expect(bars.contains("analytics.hourDistribution.accessibility.total"))
        #expect(bars.contains("analytics.hourDistribution.accessibility.task"))
        #expect(bars.contains("analytics.hourDistribution.accessibility.empty"))
        #expect(bars.contains(".accessibilityElement(children: .ignore)"))
        #expect(bars.contains(".accessibilityValue(accessibilityValue)"))
        #expect(bars.contains("%02d:00") == false)
    }

    @Test
    func customSelectorsExposeSelectionAndReadableColorNames() throws {
        let symbolPicker = try sourceText("timetracker/Features/Tasks/Editor/SymbolPickerViews.swift")
        let quickStart = try sourceText("timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift")
        let colors = try sourceText("timetracker/SharedUI/Foundation/ColorSupport.swift")

        #expect(symbolPicker.components(separatedBy: ".accessibilityAddTraits(").count - 1 >= 2)
        #expect(symbolPicker.contains("TaskColorPalette.accessibilityName(for: hex)"))
        #expect(symbolPicker.contains("editor.symbol.symbolValue"))
        #expect(quickStart.contains(".accessibilityAddTraits(pinned ? .isSelected : [])"))
        #expect(quickStart.contains("quickStart.selection.pinnedOrder"))
        #expect(quickStart.contains("quickStart.selection.notPinned"))
        #expect(colors.contains("color.name.royalBlue"))
        #expect(colors.contains("color.name.charcoal"))
        #expect(colors.contains("color.name.custom"))
    }
}
