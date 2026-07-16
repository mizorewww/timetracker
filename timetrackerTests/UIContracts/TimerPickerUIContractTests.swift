import Foundation
import Testing
@testable import timetracker

struct TimerPickerUIContractTests {
    @Test
    func runningRowsExposeStatusAndASeparateStopButton() throws {
        let pickerSource = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let rowSource = try sourceText("timetracker/Features/Home/Controls/TaskStartPickerRows.swift")

        #expect(pickerSource.contains("ForEach(runningItems)"))
        #expect(pickerSource.contains("TaskStartPickerRunningRow("))
        #expect(pickerSource.contains("timer.taskPicker.running."))
        #expect(pickerSource.contains("store.stop(segment: activeSegment)"))
        #expect(rowSource.contains("timer.taskPicker.stop."))
        #expect(rowSource.contains("Button(action: onStop)"))
        #expect(rowSource.contains(".accessibilityElement(children: .ignore)"))
        #expect(rowSource.contains("timer.action.stopTaskFormat"))
        #expect(rowSource.contains("timer.picker.runningTaskFormat"))
        #expect(rowSource.contains("timer.picker.runningHint"))
    }

    @Test
    func selectableRowsOnlyStartOrExplicitlySwitch() throws {
        let viewSource = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let rowSource = try sourceText("timetracker/Features/Home/Controls/TaskStartPickerRows.swift")
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TimerCommands.swift")
        let commandSource = try sourceText("timetracker/Commands/TimerPickerCommands.swift")

        #expect(viewSource.contains("ForEach(selectableItems)"))
        #expect(viewSource.contains("store.performTimerPickerSelection(item.task)"))
        #expect(viewSource.contains("if outcome.shouldDismissPicker"))
        #expect(viewSource.contains("timer.taskPicker.select."))
        #expect(rowSource.contains("timer.task.switchHint"))
        #expect(viewSource.contains("activeSegment == nil ? \"timer.task.startHint\" : \"timer.task.stopHint\"") == false)
        #expect(storeSource.contains("case .alreadyRunning:\n            return .alreadyRunning"))
        #expect(storeSource.contains("case .switchTimer:\n            return startTask(task) ? .switched : .failed"))
        #expect(commandSource.contains("guard isTaskRunning == false else { return .alreadyRunning }"))
    }

    @Test
    func normalRowsGiveTaskIdentityPriorityOverCommands() throws {
        let pickerSource = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let rowSource = try sourceText("timetracker/Features/Home/Controls/TaskStartPickerRows.swift")

        #expect(rowSource.contains("HStack(alignment: .top, spacing: 12)"))
        #expect(rowSource.contains("VStack(alignment: .leading, spacing: 8)"))
        #expect(rowSource.contains("TaskStartPickerTaskText("))
        #expect(rowSource.contains(".lineLimit(2)"))
        #expect(rowSource.contains(".foregroundStyle(Color.primary)"))
        #expect(rowSource.contains(".foregroundStyle(Color.secondary)"))
        #expect(rowSource.contains("let parentPath: String?"))
        #expect(rowSource.contains("RunningStatusBadge()\n                        .accessibilityHidden(true)"))
        #expect(pickerSource.contains("parentPath: store.parentPath(for: task)"))
        #expect(pickerSource.contains("placement: .navigationBarDrawer(displayMode: .always)"))
        #expect(pickerSource.contains(".listSectionSpacing(18)"))
        #expect(rowSource.contains(".symbolRenderingMode(.monochrome)"))
        #expect(rowSource.contains(".foregroundStyle(Color.red)"))
    }

    @Test
    func pickerCopyExplainsStartSwitchAndStopConsequencesInEveryLocale() throws {
        let localizationPaths = [
            "timetracker/en.lproj/Localizable.strings",
            "timetracker/zh-Hans.lproj/Localizable.strings",
            "timetracker/zh-Hant.lproj/Localizable.strings"
        ]
        let keys = [
            "timer.task.switchHint",
            "timer.picker.runningHeader",
            "timer.picker.availableHeader",
            "timer.picker.switchHeader",
            "timer.picker.startFooter",
            "timer.picker.parallelFooter",
            "timer.picker.switchFooter",
            "timer.picker.action.start",
            "timer.picker.action.switch",
            "timer.picker.startTaskFormat",
            "timer.picker.switchTaskFormat",
            "timer.picker.runningTaskFormat",
            "timer.picker.runningHint"
        ]

        for path in localizationPaths {
            let source = try sourceText(path)
            for key in keys {
                #expect(source.contains("\"\(key)\" ="))
            }
        }
    }
}
