import Foundation

struct TaskEditorDraftBaseline: Equatable {
    let taskMutationID: UUID
    let checklistItemMutationIDs: [UUID: UUID]
    let checklistVisualMutationIDs: [UUID: UUID]
    let categoryAssignmentMutationID: UUID?
}

struct TaskEditorDraft: Identifiable, Equatable {
    let id = UUID()
    let baseline: TaskEditorDraftBaseline?
    var taskID: UUID?
    var title: String
    var status: TaskStatus
    var parentID: UUID?
    var categoryID: UUID?
    var colorHex: String
    var iconName: String
    var notes: String
    var estimatedMinutes: Int?
    var hasDueDate: Bool
    var dueAt: Date
    var checklistItems: [ChecklistEditorDraft]

    init(parentID: UUID?, categoryID: UUID? = nil) {
        self.baseline = nil
        self.taskID = nil
        self.title = ""
        self.status = .active
        self.parentID = parentID
        self.categoryID = parentID == nil ? categoryID : nil
        self.colorHex = "1677FF"
        self.iconName = "checkmark.circle"
        self.notes = ""
        self.estimatedMinutes = nil
        self.hasDueDate = false
        self.dueAt = Date()
        self.checklistItems = []
    }

    init(
        task: TaskNode,
        categoryID: UUID? = nil,
        categoryAssignment: TaskCategoryAssignment? = nil,
        checklistItems: [ChecklistItem],
        visualByChecklistID: [UUID: ChecklistItemVisual] = [:]
    ) {
        let checklistItemMutationIDs = checklistItems.reduce(into: [UUID: UUID]()) {
            $0[$1.id] = $1.clientMutationID
        }
        self.baseline = TaskEditorDraftBaseline(
            taskMutationID: task.clientMutationID,
            checklistItemMutationIDs: checklistItemMutationIDs,
            checklistVisualMutationIDs: visualByChecklistID.reduce(into: [UUID: UUID]()) {
                guard checklistItemMutationIDs[$1.key] != nil else { return }
                $0[$1.key] = $1.value.clientMutationID
            },
            categoryAssignmentMutationID: categoryAssignment?.clientMutationID
        )
        self.taskID = task.id
        self.title = task.title
        self.status = task.status
        self.parentID = task.parentID
        self.categoryID = task.parentID == nil ? categoryID : nil
        self.colorHex = task.colorHex ?? "1677FF"
        self.iconName = task.iconName ?? "checkmark.circle"
        self.notes = task.notes ?? ""
        self.estimatedMinutes = TaskEstimatePolicy.normalized(seconds: task.estimatedSeconds).map { $0 / 60 }
        self.hasDueDate = task.dueAt != nil
        self.dueAt = task.dueAt ?? Date()
        self.checklistItems = checklistItems.map { item in
            ChecklistEditorDraft(item: item, visual: visualByChecklistID[item.id])
        }
    }
}

struct TaskCategoryEditorDraft: Identifiable, Equatable {
    let id = UUID()
    var categoryID: UUID?
    var title: String
    var colorHex: String
    var iconName: String
    var includesInForecast: Bool

    init() {
        self.categoryID = nil
        self.title = ""
        self.colorHex = "1677FF"
        self.iconName = "square.grid.2x2"
        self.includesInForecast = true
    }

    init(category: TaskCategory) {
        self.categoryID = category.id
        self.title = category.title
        self.colorHex = category.colorHex ?? "1677FF"
        self.iconName = category.iconName ?? "square.grid.2x2"
        self.includesInForecast = category.includesInForecast
    }
}

struct ChecklistEditorDraft: Identifiable, Equatable {
    let id: UUID
    var existingID: UUID?
    var title: String
    var isCompleted: Bool
    var iconName: String
    var colorHex: String

    nonisolated init(
        title: String = "",
        isCompleted: Bool = false,
        iconName: String = "checkmark.circle",
        colorHex: String = "1677FF"
    ) {
        self.id = UUID()
        self.existingID = nil
        self.title = title
        self.isCompleted = isCompleted
        self.iconName = iconName
        self.colorHex = colorHex
    }

    nonisolated init(item: ChecklistItem, visual: ChecklistItemVisual? = nil) {
        self.id = item.id
        self.existingID = item.id
        self.title = item.title
        self.isCompleted = item.isCompleted
        self.iconName = visual?.iconName ?? "checkmark.circle"
        self.colorHex = visual?.colorHex ?? "1677FF"
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
        self.inboxItemID = item.id
        self.taskID = suggestion?.taskID ?? item.suggestedTaskID ?? fallbackTaskID
        self.reason = suggestion?.reason ?? item.suggestionReason ?? ""
        self.iconName = suggestion?.iconName ?? "checkmark.circle"
        self.colorHex = suggestion?.colorHex ?? "1677FF"
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
        self.startedAt = end.addingTimeInterval(-30 * 60)
        self.endedAt = end
        self.note = ""
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
        self.segmentID = segment.id
        self.taskID = segment.taskID
        self.startedAt = segment.startedAt
        self.endedAt = segment.endedAt ?? Date()
        let isActive = segment.endedAt == nil
        self.wasActive = isActive
        self.isActive = isActive
        self.note = note
        self.source = segment.source
        self.baseline = SegmentEditorDraftBaseline(
            segment: segment,
            sessionMutationID: sessionMutationID,
            pomodoroPhase: pomodoroPhase
        )
    }
}
