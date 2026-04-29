import Foundation

struct TaskEditorDraft: Identifiable {
    let id = UUID()
    var taskID: UUID?
    var title: String
    var status: TaskStatus
    var parentID: UUID?
    var colorHex: String
    var iconName: String
    var notes: String
    var estimatedMinutes: Int?
    var hasDueDate: Bool
    var dueAt: Date
    var checklistItems: [ChecklistEditorDraft]

    init(parentID: UUID?) {
        self.taskID = nil
        self.title = ""
        self.status = .active
        self.parentID = parentID
        self.colorHex = "1677FF"
        self.iconName = "checkmark.circle"
        self.notes = ""
        self.estimatedMinutes = nil
        self.hasDueDate = false
        self.dueAt = Date()
        self.checklistItems = []
    }

    init(task: TaskNode, checklistItems: [ChecklistItem]) {
        self.taskID = task.id
        self.title = task.title
        self.status = task.status
        self.parentID = task.parentID
        self.colorHex = task.colorHex ?? "1677FF"
        self.iconName = task.iconName ?? "checkmark.circle"
        self.notes = task.notes ?? ""
        self.estimatedMinutes = task.estimatedSeconds.map { $0 / 60 }
        self.hasDueDate = task.dueAt != nil
        self.dueAt = task.dueAt ?? Date()
        self.checklistItems = checklistItems.map(ChecklistEditorDraft.init(item:))
    }
}

struct ChecklistEditorDraft: Identifiable, Equatable {
    let id: UUID
    var existingID: UUID?
    var title: String
    var isCompleted: Bool

    nonisolated init(title: String = "", isCompleted: Bool = false) {
        self.id = UUID()
        self.existingID = nil
        self.title = title
        self.isCompleted = isCompleted
    }

    nonisolated init(item: ChecklistItem) {
        self.id = item.id
        self.existingID = item.id
        self.title = item.title
        self.isCompleted = item.isCompleted
    }
}

struct ManualTimeDraft: Identifiable {
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

struct SegmentEditorDraft: Identifiable {
    let id = UUID()
    let segmentID: UUID
    var taskID: UUID?
    var startedAt: Date
    var endedAt: Date
    var isActive: Bool
    var note: String
    var source: TimeSessionSource

    init(segment: TimeSegment, note: String) {
        self.segmentID = segment.id
        self.taskID = segment.taskID
        self.startedAt = segment.startedAt
        self.endedAt = segment.endedAt ?? Date()
        self.isActive = segment.endedAt == nil
        self.note = note
        self.source = segment.source
    }
}

struct SyncStatus {
    let mode: String
    let containerIdentifier: String
    let deviceID: String
    let lastError: String?
    let accountStatus: String

    var isCloudBacked: Bool {
        mode == "iCloud"
    }

    var storageStatusText: String {
        isCloudBacked ? "SwiftData + iCloud" : mode
    }
}

enum AnalyticsRange: String, CaseIterable, Identifiable {
    case today = "Today"
    case week = "Week"
    case month = "Month"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today:
            return AppStrings.localized("analytics.range.today")
        case .week:
            return AppStrings.localized("analytics.range.week")
        case .month:
            return AppStrings.localized("analytics.range.month")
        }
    }
}

struct AnalyticsOverview {
    let grossSeconds: Int
    let wallSeconds: Int
    let overlapSeconds: Int
    let pomodoroCount: Int
    let averageFocusSeconds: Int
}

struct DailyAnalyticsPoint: Identifiable {
    let date: Date
    let grossSeconds: Int
    let wallSeconds: Int
    let label: String

    var id: Date { date }
}

struct HourlyAnalyticsPoint: Identifiable {
    let hour: Int
    let grossSeconds: Int
    let wallSeconds: Int

    var id: Int { hour }
    var label: String {
        hour == 0 ? "00" : "\(hour)"
    }
}

struct TaskAnalyticsPoint: Identifiable {
    let taskID: UUID
    let title: String
    let path: String
    let colorHex: String?
    let iconName: String?
    let status: TaskStatus?
    let grossSeconds: Int
    let wallSeconds: Int

    var id: UUID { taskID }
}

struct OverlapAnalyticsPoint: Identifiable {
    let start: Date
    let end: Date
    let firstTitle: String
    let secondTitle: String

    var id: String {
        "\(Int(start.timeIntervalSince1970))-\(Int(end.timeIntervalSince1970))-\(firstTitle)-\(secondTitle)"
    }

    var durationSeconds: Int {
        max(0, Int(end.timeIntervalSince(start)))
    }
}
