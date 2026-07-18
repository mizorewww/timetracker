import Foundation
import Testing
@testable import timetracker

struct TimerPickerUIContractTests {
    @Test
    func runningRowsExposeStatusAndASeparateStopButton() throws {
        let pickerSource = try taskHierarchyPickerSource()

        #expect(pickerSource.contains("ForEach(projection.runningItems)"))
        #expect(pickerSource.contains("func runningRow("))
        #expect(pickerSource.contains("timer.taskPicker.running."))
        #expect(pickerSource.contains("store.stop(segment: activeSegment)"))
        #expect(pickerSource.contains("timer.taskPicker.stop."))
        #expect(pickerSource.contains("func stopButton("))
        #expect(pickerSource.contains(".accessibilityElement(children: .ignore)"))
        #expect(pickerSource.contains("timer.action.stopTaskFormat"))
        #expect(pickerSource.contains("timer.picker.runningTaskFormat"))
        #expect(pickerSource.contains("timer.picker.runningHint"))
    }

    @Test
    func selectableRowsOnlyStartOrExplicitlySwitch() throws {
        let viewSource = try taskHierarchyPickerSource()
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+TimerCommands.swift")
        let commandSource = try sourceText("timetracker/Commands/TimerPickerCommands.swift")

        #expect(viewSource.contains("ForEach(items)"))
        #expect(viewSource.contains("store.performTimerPickerSelection(task)"))
        #expect(viewSource.contains("if outcome.shouldDismissPicker"))
        #expect(viewSource.contains("timer.taskPicker.select."))
        #expect(viewSource.contains("timer.task.switchHint"))
        #expect(viewSource.contains("activeSegment == nil ? \"timer.task.startHint\" : \"timer.task.stopHint\"") == false)
        #expect(storeSource.contains("case .alreadyRunning:\n            return .alreadyRunning"))
        #expect(storeSource.contains("case .switchTimer:\n            return startTask(task) ? .switched : .failed"))
        #expect(commandSource.contains("guard isTaskRunning == false else { return .alreadyRunning }"))
    }

    @Test
    func normalRowsGiveTaskIdentityPriorityOverCommands() throws {
        let pickerSource = try taskHierarchyPickerSource()
        let identitySource = try sourceText(
            "timetracker/SharedUI/Components/TaskIdentityRow.swift"
        )
        let projectionSource = try sourceText(
            "timetracker/SharedUI/Components/TaskHierarchyProjection.swift"
        )

        #expect(identitySource.contains("HStack(alignment: .top, spacing: 12)"))
        #expect(pickerSource.contains("VStack(alignment: .leading, spacing: 8)"))
        #expect(pickerSource.contains("TaskIdentityRow("))
        #expect(identitySource.contains(".lineLimit(2)"))
        #expect(identitySource.contains("let text = presentation.text(for: context)"))
        #expect(identitySource.contains("TaskWorkBlockedStatusBadge()"))
        #expect(pickerSource.contains("RunningStatusBadge()\n                    .accessibilityHidden(true)"))
        #expect(projectionSource.contains("store.taskIdentityPresentation(for: task)"))
        #expect(pickerSource.contains("sectionKind == .hierarchy ? .hierarchical : .standard"))
        #expect(pickerSource.contains("placement: .navigationBarDrawer(displayMode: .always)"))
        #expect(pickerSource.contains(".listSectionSpacing(18)"))
        #expect(pickerSource.contains(".symbolRenderingMode(.monochrome)"))
        #expect(pickerSource.contains(".foregroundStyle(Color.red)"))
    }

    @Test
    func searchNoResultsPrioritizesClearingTheQueryOverCreatingData() throws {
        let pickerSource = try taskHierarchyPickerSource()

        #expect(pickerSource.contains("if projection.isSearching"))
        #expect(pickerSource.contains("tasks.search.clear"))
        #expect(pickerSource.contains("searchText = \"\""))
        #expect(pickerSource.contains(".buttonStyle(.borderedProminent)"))
        #expect(pickerSource.contains("isSecondary: projection.isSearching"))
        #expect(pickerSource.contains("private func createTaskButton("))
        #expect(pickerSource.contains(".buttonStyle(.bordered)"))
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

    private func taskHierarchyPickerSource() throws -> String {
        try [
            "timetracker/SharedUI/Components/TaskHierarchyPicker.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerBehavior.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerPresentation.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
    }
}
