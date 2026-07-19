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
            "timetrackerLiveActivityExtension/LiveActivityTimerViews.swift",
            "timetrackerLiveActivityExtension/LiveActivityTimerPresentationViews.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(widget.contains(".accessibilityValue(elapsedAccessibilityValue)"))
        #expect(widget.contains("private var elapsedAccessibilityValue: Text"))
        #expect(widget.contains("Text(startedAt, style: .timer)"))
        #expect(widget.contains("Text(WidgetElapsedFormatter.clock(seconds))"))
        #expect(widget.contains(".accessibilityValue(Text(generatedAt, style: .relative))"))
        #expect(liveActivity.contains("struct CompactTimerText"))
        #expect(liveActivity.contains(".accessibilityValue(elapsedAccessibilityValue)"))
        #expect(liveActivity.contains("Text(LiveActivityElapsedFormatter.clock(seconds))"))
        #expect(liveActivity.contains("live.timer.staleHint"))
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
        let symbolPicker = try [
            "timetracker/Features/Tasks/Editor/SymbolPickerViews.swift",
            "timetracker/Features/Tasks/Editor/SymbolColorWell.swift"
        ].map(sourceText).joined(separator: "\n")
        let quickStart = try sourceText("timetracker/Features/Home/Sections/HomeQuickStartEditorViews.swift")
        let colors = try sourceText("timetracker/SharedUI/Foundation/ColorSupport.swift")

        #expect(symbolPicker.contains(".accessibilityAddTraits(symbolName == symbol"))
        #expect(symbolPicker.contains("editor.symbol.symbolValue"))
        #expect(symbolPicker.contains("TaskColorPalette.accessibilityName(for: selection)"))
        #expect(symbolPicker.contains("TaskColorPalette.contrastingForegroundColor(for: colorHex)"))
        #expect(symbolPicker.contains("symbol.picker.color.well"))
        #expect(symbolPicker.contains("symbol.picker.color.blossom"))
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
        #expect(sidebar.contains("isRunning: isRunning"))
        #expect(sidebar.contains("values.append(AppStrings.running)"))
        #expect(sidebar.contains("blocked: blocked") == false)
        #expect(sidebar.contains("private var disclosureTargetSize: CGFloat"))
    }

    @Test
    func taskTimerSurfacesSeparatePassiveStateFromExplicitStopActions() throws {
        let summary = try sourceText(
            "timetracker/SharedUI/Components/TaskSummaryRow.swift"
        )
        let tasks = try [
            "timetracker/Features/Tasks/Management/TaskManagementRowViews.swift",
            "timetracker/Features/Tasks/Management/TaskManagementAccessibility.swift"
        ].map(sourceText).joined(separator: "\n")
        let pickerRows = try sourceText(
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift"
        )
        let timerAction = try sourceText(
            "timetracker/SharedUI/Components/TaskTimerActionButton.swift"
        )

        #expect(summary.contains("struct TaskRunningIndicator"))
        #expect(summary.contains(".accessibilityLabel(AppStrings.running)"))
        #expect(tasks.contains("components.append(AppStrings.running)"))
        #expect(tasks.contains("store.stop(") == false)
        #expect(pickerRows.contains("RunningStatusBadge()") == false)
        #expect(pickerRows.contains("TaskTimerActionButton("))
        #expect(timerAction.contains("timer.action.stopTaskFormat"))
        #expect(timerAction.contains("timer.task.stopHint"))
    }

    @Test
    func pomodoroSelectionControlsKeepTaskIdentityAndUseARealTaskPicker() throws {
        let source = try sourceText(
            "timetracker/Features/Pomodoro/Sections/PomodoroSetupSelectionViews.swift"
        )

        #expect(source.components(separatedBy: "Menu {").count - 1 == 1)
        #expect(source.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(source.contains("let onChooseTask: () -> Void"))
        #expect(source.contains("Button(action: onChooseTask)"))
        #expect(source.contains("$focusTaskID") == false)
        #expect(source.contains("$store.selectedTaskID") == false)
        #expect(source.contains("selectedTask.flatMap(store.parentPath(for:))"))
        #expect(source.components(separatedBy: ".buttonStyle(.bordered)").count - 1 == 2)
        #expect(source.contains(".appCard(") == false)
        #expect(source.contains("pomodoro.planPicker"))
        #expect(source.contains("pomodoro.taskPicker.open"))
    }
}
