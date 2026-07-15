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
    func timerExtensionsExposeLiveAndFrozenAccessibilityValues() throws {
        let widget = try [
            "timetrackerWidgetExtension/ActiveTimerWidgetView.swift",
            "timetrackerWidgetExtension/WidgetSupplementaryViews.swift"
        ].map(sourceText).joined(separator: "\n")
        let liveActivity = try [
            "timetrackerLiveActivityExtension/TimeTrackerLiveActivityBundle.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(widget.contains(".accessibilityValue(elapsedAccessibilityValue)"))
        #expect(widget.contains("private var elapsedAccessibilityValue: Text"))
        #expect(widget.contains("Text(startedAt, style: .timer)"))
        #expect(widget.contains("Text(WidgetElapsedFormatter.clock(seconds))"))
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

    @Test
    func analyticsAndSidebarVisualsKeepEquivalentVoiceOverSemantics() throws {
        let metrics = try sourceText("timetracker/SharedUI/Components/MetricCards.swift")
        let groups = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsGroupBreakdownViews.swift")
        let trend = try sourceText("timetracker/Features/Analytics/Sections/AnalyticsTrendViews.swift")
        let sidebar = try sourceText("timetracker/Features/Sidebar/SidebarTaskTreeViews.swift")

        #expect(metrics.contains(".accessibilityElement(children: .ignore)"))
        #expect(metrics.contains(".accessibilityLabel(metric.title)"))
        #expect(groups.contains(".accessibilityHidden(true)"))
        #expect(trend.components(separatedBy: ".accessibilityLabel(point.label)").count - 1 == 2)
        #expect(trend.contains("DurationFormatter.compact(point.wallSeconds)"))
        #expect(trend.contains("DurationFormatter.compact(point.grossSeconds)"))
        #expect(sidebar.contains(".accessibilityLabel(task.title)"))
        #expect(sidebar.contains("accessibilityValue(progress: progress, childCount: childCount, blocked: blocked)"))
        #expect(sidebar.contains("private var disclosureTargetSize: CGFloat"))
    }

    @Test
    func pomodoroMenusLetAccessibilityTextDetermineRowHeight() throws {
        let source = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift"
        )

        #expect(source.components(separatedBy: "Menu {").count - 1 == 2)
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(source.components(separatedBy: ".appCard(padding: 14)").count - 1 == 2)
        #expect(source.contains(".buttonStyle(.bordered)") == false)
        #expect(source.contains("pomodoro.planPicker"))
        #expect(source.contains("pomodoro.taskPicker"))
    }
}
