import Foundation
import SwiftData

extension TimeTrackerStore {
    func addCountdownEvent() {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.add(context: modelContext)
        }
    }

    func updateCountdownEvent(_ event: CountdownEvent, title: String? = nil, date: Date? = nil) {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.update(event, title: title, date: date, context: modelContext)
        }
    }

    func deleteCountdownEvent(_ event: CountdownEvent) {
        perform(event: .countdownChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try countdownCommandHandler.softDelete(event, context: modelContext)
        }
    }

    func startSelectedTask() {
        guard let selectedTaskID else { return }
        startTask(taskID: selectedTaskID)
    }

    func selectTask(_ taskID: UUID, revealInToday: Bool = true) {
        selectedTaskID = taskID
        if revealInToday {
            desktopDestination = .today
        }
        selectedTaskPulseID = taskID
        selectedTaskPulseToken = UUID()
    }

    func startTask(_ task: TaskNode) {
        selectTask(task.id, revealInToday: false)
        startTask(taskID: task.id)
    }

    private func startTask(taskID: UUID) {
        perform(event: .timerChanged(taskID: taskID)) {
            try timerCommandHandler.startTask(
                taskID: taskID,
                allowParallelTimers: preferences.allowParallelTimers,
                activeSegments: activeSegments,
                pausedSessions: pausedSessions,
                pomodoroRuns: pomodoroRuns,
                timeRepository: requiredTimeRepository(),
                context: modelContext
            )
        }
    }

    func stop(segment: TimeSegment) {
        perform(event: .timerChanged(taskID: segment.taskID)) {
            try timerCommandHandler.stop(segment: segment, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func pause(segment: TimeSegment) {
        perform(event: .timerChanged(taskID: segment.taskID)) {
            try timerCommandHandler.pause(segment: segment, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func resume(session: TimeSession) {
        perform(event: .timerChanged(taskID: session.taskID)) {
            try timerCommandHandler.resume(session: session, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func stop(session: TimeSession) {
        perform(event: .timerChanged(taskID: session.taskID)) {
            try timerCommandHandler.stop(session: session, pomodoroRuns: pomodoroRuns, timeRepository: requiredTimeRepository(), context: modelContext)
        }
    }

    func presentNewTask(parentID: UUID? = nil) {
        taskEditorDraft = TaskEditorDraft(parentID: parentID)
    }

    func presentEditTask(_ task: TaskNode) {
        taskEditorDraft = TaskEditorDraft(task: task, checklistItems: checklistItems(for: task.id))
    }

    @discardableResult
    func saveTaskDraft(_ draft: TaskEditorDraft) -> Bool {
        let sanitizedTitle = draft.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !sanitizedTitle.isEmpty else {
            errorMessage = AppStrings.localized("task.nameRequired")
            return false
        }

        let didSave = perform(events: [.taskTreeChanged(taskID: draft.taskID), .checklistChanged(taskID: draft.taskID)]) {
            selectedTaskID = try taskDraftCommandHandler.save(
                draft: draft,
                sanitizedTitle: sanitizedTitle,
                taskRepository: requiredTaskRepository(),
                saveChecklistDrafts: saveChecklistDrafts
            )
        }
        if didSave {
            taskEditorDraft = nil
        }
        return didSave
    }

    func setPreferredColorScheme(_ value: String) {
        setPreference(.preferredColorScheme, valueJSON: PreferenceJSON.encode(value))
    }

    func setPomodoroDefaultMode(_ value: String) {
        setPreference(.pomodoroDefaultMode, valueJSON: PreferenceJSON.encode(value))
    }

    func setDefaultFocusMinutes(_ value: Int) {
        setPreference(.defaultFocusMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultBreakMinutes(_ value: Int) {
        setPreference(.defaultBreakMinutes, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...480)))
    }

    func setDefaultPomodoroRounds(_ value: Int) {
        setPreference(.defaultPomodoroRounds, valueJSON: PreferenceJSON.encode(value.clamped(to: 1...24)))
    }

    func setAllowParallelTimers(_ value: Bool) {
        setPreference(.allowParallelTimers, valueJSON: PreferenceJSON.encode(value))
    }

    func setShowGrossAndWallTogether(_ value: Bool) {
        setPreference(.showGrossAndWallTogether, valueJSON: PreferenceJSON.encode(value))
    }

    func setCloudSyncEnabled(_ value: Bool) {
        setPreference(.cloudSyncEnabled, valueJSON: PreferenceJSON.encode(value))
        UserDefaults.standard.set(value, forKey: AppCloudSync.enabledKey)
    }

    func setQuickStartTaskIDs(_ ids: [UUID]) {
        setPreference(.quickStartTaskIDs, valueJSON: PreferenceJSON.encode(ids.map(\.uuidString)))
    }

    func archiveSelectedTask(taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(event: .taskTreeChanged(taskID: targetID)) {
            try taskDraftCommandHandler.archive(taskID: targetID, repository: requiredTaskRepository())
            if self.selectedTaskID == targetID {
                self.selectedTaskID = tasks.first(where: { $0.id != targetID })?.id
            }
        }
    }

    func setTaskStatus(_ status: TaskStatus, taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(event: .taskTreeChanged(taskID: targetID)) {
            try taskDraftCommandHandler.setStatus(status, taskID: targetID, repository: requiredTaskRepository())
        }
    }

    func deleteSelectedTask(taskID: UUID? = nil) {
        let targetID = taskID ?? selectedTaskID
        guard let targetID else { return }
        perform(event: .taskTreeChanged(taskID: targetID)) {
            try taskDraftCommandHandler.softDelete(taskID: targetID, repository: requiredTaskRepository())
            if self.selectedTaskID == targetID {
                self.selectedTaskID = tasks.first(where: { $0.id != targetID })?.id
            }
        }
    }

    func presentManualTime(taskID: UUID? = nil) {
        let target = taskID ?? selectedTaskID ?? tasks.first?.id
        manualTimeDraft = ManualTimeDraft(taskID: target, tasks: tasks)
    }

    func saveManualTimeDraft(_ draft: ManualTimeDraft) {
        guard let taskID = draft.taskID else {
            errorMessage = AppStrings.localized("task.selectRequired")
            return
        }
        guard draft.endedAt > draft.startedAt else {
            errorMessage = AppStrings.localized("time.endAfterStart")
            return
        }

        perform(event: .ledgerHistoryChanged(taskID: taskID, range: StoreInvalidationRange(start: draft.startedAt, end: draft.endedAt))) {
            try ledgerCommandHandler.addManualTime(draft: draft, taskID: taskID, repository: requiredTimeRepository())
        }
        manualTimeDraft = nil
    }

    func presentEditSegment(_ segment: TimeSegment) {
        segmentEditorDraft = SegmentEditorDraft(segment: segment, note: note(for: segment))
    }

    func saveSegmentDraft(_ draft: SegmentEditorDraft) {
        guard let taskID = draft.taskID else {
            errorMessage = AppStrings.localized("task.selectRequired")
            return
        }

        let endedAt = draft.isActive ? nil : draft.endedAt
        if let endedAt, endedAt <= draft.startedAt {
            errorMessage = AppStrings.localized("time.endAfterStart")
            return
        }

        perform(event: .ledgerHistoryChanged(taskID: taskID, range: StoreInvalidationRange(start: draft.startedAt, end: draft.endedAt))) {
            try ledgerCommandHandler.updateSegment(draft: draft, taskID: taskID, repository: requiredTimeRepository())
            selectedTaskID = taskID
        }
        segmentEditorDraft = nil
    }

    func deleteSegment(_ segmentID: UUID) {
        perform(event: .ledgerHistoryChanged(taskID: segmentEditorDraft?.taskID, range: nil)) {
            try ledgerCommandHandler.softDeleteSegment(segmentID, repository: requiredTimeRepository())
        }
        segmentEditorDraft = nil
    }

    func replaceWithDemoData() {
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.replaceWithDemoData(context: modelContext)
        }
    }

    func clearAllData() {
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.clearAll(context: modelContext)
            selectedTaskID = nil
        }
    }

    func clearDemoData() {
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            try SeedData.clearDemoData(context: modelContext)
            if let selectedTaskID, tasks.contains(where: { $0.id == selectedTaskID && $0.deviceID == "demo" }) {
                self.selectedTaskID = nil
            }
        }
    }

    @discardableResult
    func optimizeDatabase() -> Int {
        var removedCount = 0
        perform {
            guard let modelContext else { throw StoreError.notConfigured }
            removedCount = try databaseMaintenanceService.optimizeDatabase(context: modelContext)
        }
        return removedCount
    }

    func csvExport() -> String {
        csvExportService.export(
            segments: allSegments,
            sessions: sessions,
            taskByID: taskByID,
            taskParentPathByID: taskParentPathByID
        )
    }

    func startPomodoroForSelectedTask(focusSeconds: Int = 25 * 60, breakSeconds: Int = 5 * 60, targetRounds: Int = 1) {
        guard let selectedTaskID else {
            errorMessage = AppStrings.localized("task.selectBeforePomodoro")
            return
        }
        perform(event: .pomodoroChanged(taskID: selectedTaskID)) {
            _ = try pomodoroCommandHandler.start(
                taskID: selectedTaskID,
                focusSeconds: focusSeconds,
                breakSeconds: breakSeconds,
                targetRounds: targetRounds,
                allowParallelTimers: preferences.allowParallelTimers,
                activeSegments: activeSegments,
                pomodoroRuns: pomodoroRuns,
                timeRepository: requiredTimeRepository(),
                pomodoroRepository: requiredPomodoroRepository(),
                context: modelContext
            )
        }
    }

    func completeActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        perform(event: .pomodoroChanged(taskID: run.taskID)) {
            try pomodoroCommandHandler.complete(run: run, repository: requiredPomodoroRepository())
        }
    }

    func cancelActivePomodoro() {
        guard let run = activePomodoroRun else { return }
        perform(event: .pomodoroChanged(taskID: run.taskID)) {
            try pomodoroCommandHandler.cancel(run: run, repository: requiredPomodoroRepository())
        }
    }

    func toggleChecklistItem(_ item: ChecklistItem) {
        perform(event: .checklistChanged(taskID: item.taskID)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.toggle(item, context: modelContext)
        }
    }

    func addChecklistItem(taskID: UUID, title: String) {
        perform(event: .checklistChanged(taskID: taskID)) {
            guard let modelContext else { throw StoreError.notConfigured }
            try checklistCommandHandler.add(
                taskID: taskID,
                title: title,
                existingItems: checklistItems(for: taskID),
                context: modelContext
            )
        }
    }


    private func setPreference(_ key: AppPreferenceKey, valueJSON: String) {
        perform(event: .preferencesChanged) {
            guard let modelContext else { throw StoreError.notConfigured }
            try preferenceCommandHandler.set(key: key, valueJSON: valueJSON, context: modelContext)
        }
    }

    private func saveChecklistDrafts(_ drafts: [ChecklistEditorDraft], taskID: UUID) throws {
        guard let modelContext else { throw StoreError.notConfigured }
        try checklistDraftService.save(drafts: drafts, taskID: taskID, context: modelContext)
    }
}
