import Foundation
import SwiftData

extension TimeTrackerSchemaV13 {
    /// Frozen V13 shape. Do not add current ChecklistItem fields here.
    @Model
    final class ChecklistItem {
        var id: UUID = UUID()
        var taskID: UUID = UUID()
        var title: String = ""
        var isCompleted: Bool = false
        var sortOrder: Double = 0
        var completedAt: Date?
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var deletedAt: Date?
        var deviceID: String = ""
        var clientMutationID: UUID = UUID()

        init(
            taskID: UUID,
            title: String,
            isCompleted: Bool = false,
            sortOrder: Double = 0,
            completedAt: Date? = nil,
            deviceID: String
        ) {
            id = UUID()
            self.taskID = taskID
            self.title = title
            self.isCompleted = isCompleted
            self.sortOrder = sortOrder
            self.completedAt = completedAt
            createdAt = Date()
            updatedAt = Date()
            deletedAt = nil
            self.deviceID = deviceID
            clientMutationID = UUID()
        }
    }
}

/// Every schema version that shipped the frozen ChecklistItem shape resolves
/// the unqualified name to the V13 snapshot, so the live model may evolve.
extension TimeTrackerSchemaV3 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV4 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV5 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV6 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV7 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV8 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV9 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV10 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV11 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

extension TimeTrackerSchemaV12 {
    typealias ChecklistItem = TimeTrackerSchemaV13.ChecklistItem
}

enum TimeTrackerSchemaV14: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 13, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            InboxItem.self,
            InboxSuggestion.self,
            InboxCaptureReceipt.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self,
            ChecklistItemVisual.self,
            TaskRecurrenceRule.self,
            TaskRecurrenceOccurrence.self,
            TaskQuantityGoal.self,
            TaskQuantityEntry.self,
        ]
    }
}
