import Foundation

nonisolated struct TaskEditorDraftBaseline: Codable, Equatable, Sendable {
    let taskMutationID: UUID
    let checklistItemMutationIDs: [UUID: UUID]
    let checklistVisualMutationIDs: [UUID: UUID]
    let categoryAssignmentMutationID: UUID?
    let quantityGoalMutationID: UUID?
    let recurrenceRuleMutationID: UUID?
    let quantityEntryRevision: UUID?

    init(
        taskMutationID: UUID,
        checklistItemMutationIDs: [UUID: UUID],
        checklistVisualMutationIDs: [UUID: UUID],
        categoryAssignmentMutationID: UUID?,
        quantityGoalMutationID: UUID? = nil,
        recurrenceRuleMutationID: UUID? = nil,
        quantityEntryRevision: UUID? = nil
    ) {
        self.taskMutationID = taskMutationID
        self.checklistItemMutationIDs = checklistItemMutationIDs
        self.checklistVisualMutationIDs = checklistVisualMutationIDs
        self.categoryAssignmentMutationID = categoryAssignmentMutationID
        self.quantityGoalMutationID = quantityGoalMutationID
        self.recurrenceRuleMutationID = recurrenceRuleMutationID
        self.quantityEntryRevision = quantityEntryRevision
    }
}

nonisolated struct TaskEditorDraft: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var baseline: TaskEditorDraftBaseline?
    var taskID: UUID?
    var title: String
    var parentID: UUID?
    var categoryID: UUID?
    var colorHex: String
    var iconName: String
    var notes: String
    var estimatedMinutes: Int?
    var hasDueDate: Bool
    var dueAt: Date
    var checklistItems: [ChecklistEditorDraft]
    var quantityGoal: TaskQuantityGoalDraft?
    var confirmsQuantityProgressReset = false
    var dailyRecurrence: TaskDailyRecurrenceDraft?

    /// A destructive confirmation is one-shot authority. Recovery payloads
    /// preserve the draft content but deliberately never persist this flag.
    private enum CodingKeys: String, CodingKey {
        case id
        case baseline
        case taskID
        case title
        case parentID
        case categoryID
        case colorHex
        case iconName
        case notes
        case estimatedMinutes
        case hasDueDate
        case dueAt
        case checklistItems
        case quantityGoal
        case dailyRecurrence
    }

    init(parentID: UUID?, categoryID: UUID? = nil) {
        id = UUID()
        baseline = nil
        taskID = nil
        title = ""
        self.parentID = parentID
        self.categoryID = parentID == nil ? categoryID : nil
        colorHex = "1677FF"
        iconName = "checkmark.circle"
        notes = ""
        estimatedMinutes = nil
        hasDueDate = false
        dueAt = Date()
        checklistItems = []
        quantityGoal = nil
        confirmsQuantityProgressReset = false
        dailyRecurrence = nil
    }

    @MainActor
    init(
        task: TaskNode,
        categoryID: UUID? = nil,
        categoryAssignment: TaskCategoryAssignment? = nil,
        checklistItems: [ChecklistItem],
        visualByChecklistID: [UUID: ChecklistItemVisual] = [:],
        quantityGoal: TaskQuantityGoal? = nil,
        recurrenceRule: TaskRecurrenceRule? = nil,
        quantityEntries: [TaskQuantityEntry] = []
    ) {
        id = UUID()
        let checklistItemMutationIDs = checklistItems.reduce(into: [UUID: UUID]()) {
            $0[$1.id] = $1.clientMutationID
        }
        baseline = TaskEditorDraftBaseline(
            taskMutationID: task.clientMutationID,
            checklistItemMutationIDs: checklistItemMutationIDs,
            checklistVisualMutationIDs: visualByChecklistID.reduce(into: [UUID: UUID]()) {
                guard checklistItemMutationIDs[$1.key] != nil else { return }
                $0[$1.key] = $1.value.clientMutationID
            },
            categoryAssignmentMutationID: categoryAssignment?.clientMutationID,
            quantityGoalMutationID: quantityGoal?.clientMutationID,
            recurrenceRuleMutationID: recurrenceRule?.clientMutationID,
            quantityEntryRevision: TaskQuantityEntryRevision.value(
                taskID: task.id,
                entries: quantityEntries
            )
        )
        taskID = task.id
        title = task.title
        parentID = task.parentID
        self.categoryID = task.parentID == nil ? categoryID : nil
        colorHex = task.colorHex ?? "1677FF"
        iconName = task.iconName ?? "checkmark.circle"
        notes = task.notes ?? ""
        estimatedMinutes = TaskEstimatePolicy.normalized(seconds: task.estimatedSeconds).map { $0 / 60 }
        hasDueDate = task.dueAt != nil
        dueAt = task.dueAt ?? Date()
        self.checklistItems = checklistItems.map { item in
            ChecklistEditorDraft(item: item, visual: visualByChecklistID[item.id])
        }
        self.quantityGoal = quantityGoal.map(TaskQuantityGoalDraft.init)
        confirmsQuantityProgressReset = false
        dailyRecurrence = recurrenceRule.map(
            TaskDailyRecurrenceDraft.init
        )
    }

    func copyAsNew(
        parentID: UUID?,
        categoryID: UUID?
    ) -> TaskEditorDraft {
        var copy = TaskEditorDraft(
            parentID: parentID,
            categoryID: categoryID
        )
        copy.title = title
        copy.colorHex = colorHex
        copy.iconName = iconName
        copy.notes = notes
        copy.estimatedMinutes = estimatedMinutes
        copy.hasDueDate = hasDueDate
        copy.dueAt = dueAt
        copy.quantityGoal = quantityGoal
        copy.confirmsQuantityProgressReset = false
        copy.dailyRecurrence = dailyRecurrence
        copy.checklistItems = checklistItems.map {
            ChecklistEditorDraft(
                title: $0.title,
                isCompleted: $0.isCompleted,
                iconName: $0.iconName,
                colorHex: $0.colorHex
            )
        }
        return copy
    }
}

struct InboxSuggestionEditorDraft: Identifiable, Equatable {
    let id = UUID()
    let inboxItemID: UUID
    var taskID: UUID?
    var reason: String
    var iconName: String
    var colorHex: String

    init(item: InboxItem, suggestion: InboxSuggestion? = nil, fallbackTaskID: UUID? = nil) {
        inboxItemID = item.id
        taskID = suggestion?.taskID ?? item.suggestedTaskID ?? fallbackTaskID
        reason = suggestion?.reason ?? item.suggestionReason ?? ""
        iconName = suggestion?.iconName ?? "checkmark.circle"
        colorHex = suggestion?.colorHex ?? "1677FF"
    }
}

struct ManualTimeDraft: Identifiable, Equatable {
    let id = UUID()
    var taskID: UUID?
    var startedAt: Date
    var endedAt: Date
    var note: String

    init(taskID: UUID?, tasks: [TaskNode]) {
        let end = Date()
        self.taskID = taskID ?? tasks.first?.id
        startedAt = end.addingTimeInterval(-30 * 60)
        endedAt = end
        note = ""
    }
}

nonisolated struct SegmentEditorDraftBaseline: Hashable, Sendable {
    let segmentID: UUID
    let sessionID: UUID
    let taskID: UUID
    let startedAt: Date
    let endedAt: Date?
    let sourceRaw: String
    let updatedAt: Date
    let deviceID: String
    let deletedAt: Date?
    let sessionMutationID: UUID?
    let pomodoroPhase: PomodoroPhaseToken?

    @MainActor
    init(
        segment: TimeSegment,
        sessionMutationID: UUID? = nil,
        pomodoroPhase: PomodoroPhaseToken? = nil
    ) {
        segmentID = segment.id
        sessionID = segment.sessionID
        taskID = segment.taskID
        startedAt = segment.startedAt
        endedAt = segment.endedAt
        sourceRaw = segment.sourceRaw
        updatedAt = segment.updatedAt
        deviceID = segment.deviceID
        deletedAt = segment.deletedAt
        self.sessionMutationID = sessionMutationID
        self.pomodoroPhase = pomodoroPhase
    }

    @MainActor
    func matches(
        segment: TimeSegment,
        sessionMutationID: UUID?,
        pomodoroPhase: PomodoroPhaseToken?
    ) -> Bool {
        segmentID == segment.id &&
            sessionID == segment.sessionID &&
            taskID == segment.taskID &&
            startedAt == segment.startedAt &&
            endedAt == segment.endedAt &&
            sourceRaw == segment.sourceRaw &&
            updatedAt == segment.updatedAt &&
            deviceID == segment.deviceID &&
            deletedAt == segment.deletedAt &&
            self.sessionMutationID == sessionMutationID &&
            pomodoroPhase == self.pomodoroPhase
    }
}

struct SegmentEditorDraft: Identifiable, Equatable {
    let id = UUID()
    let segmentID: UUID
    var taskID: UUID?
    var startedAt: Date
    var endedAt: Date
    let wasActive: Bool
    var isActive: Bool
    var note: String
    var source: TimeSessionSource
    let baseline: SegmentEditorDraftBaseline

    init(
        segment: TimeSegment,
        note: String,
        sessionMutationID: UUID? = nil,
        pomodoroPhase: PomodoroPhaseToken? = nil
    ) {
        segmentID = segment.id
        taskID = segment.taskID
        startedAt = segment.startedAt
        endedAt = segment.endedAt ?? Date()
        let isActive = segment.endedAt == nil
        wasActive = isActive
        self.isActive = isActive
        self.note = note
        source = segment.source
        baseline = SegmentEditorDraftBaseline(
            segment: segment,
            sessionMutationID: sessionMutationID,
            pomodoroPhase: pomodoroPhase
        )
    }
}
