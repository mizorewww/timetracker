import Foundation
import SwiftData

enum TimeTrackerSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self
        ]
    }
}

enum TimeTrackerSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 1, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self
        ]
    }
}

enum TimeTrackerSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 2, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }
}

enum TimeTrackerSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 3, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }

}

enum TimeTrackerSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 4, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }
}

enum TimeTrackerSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 5, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            TimeTrackerSchemaV9.InboxItem.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self
        ]
    }
}

enum TimeTrackerSchemaV7: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 6, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            TimeTrackerSchemaV9.InboxItem.self,
            TimeTrackerSchemaV9.InboxSuggestion.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self,
            TimeTrackerSchemaV7.ChecklistItemVisual.self
        ]
    }

}

enum TimeTrackerSchemaV8: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 7, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            TimeTrackerSchemaV9.InboxItem.self,
            TimeTrackerSchemaV9.InboxSuggestion.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self,
            ChecklistItemVisual.self
        ]
    }
}

enum TimeTrackerSchemaV9: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 8, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            TimeTrackerSchemaV9.InboxItem.self,
            TimeTrackerSchemaV9.InboxSuggestion.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self,
            ChecklistItemVisual.self
        ]
    }
}

enum TimeTrackerSchemaV10: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 9, 0)

    static var models: [any PersistentModel.Type] {
        [
            TaskNode.self,
            TaskCategory.self,
            TaskCategoryAssignment.self,
            InboxItem.self,
            InboxSuggestion.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            CountdownEvent.self,
            SyncedPreference.self,
            ChecklistItem.self,
            ChecklistItemVisual.self
        ]
    }
}

enum TimeTrackerSchemaV11: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 10, 0)

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
            ChecklistItemVisual.self
        ]
    }
}
