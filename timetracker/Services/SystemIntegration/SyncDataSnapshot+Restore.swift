import Foundation
import SwiftData

extension SyncDataSnapshot {
    /// Restores through an already store-locked fresh context. The restore is
    /// atomic inside that lock; production callers must not pass a long-lived
    /// scene context directly.
    func restoreAsLocalWinner(context: ModelContext, now: Date = Date()) throws {
        try validateForRestore()
        let deviceID = DeviceIdentity.current
        try context.performAtomicMutation {
            try restoreTasks(context: context, now: now, deviceID: deviceID)
            try restoreTaskCategories(context: context, now: now, deviceID: deviceID)
            try restoreTaskCategoryAssignments(context: context, now: now, deviceID: deviceID)
            try restoreTaskRecurrenceRules(context: context, now: now, deviceID: deviceID)
            try restoreTaskRecurrenceOccurrences(context: context, now: now, deviceID: deviceID)
            try restoreTaskQuantityGoals(context: context, now: now, deviceID: deviceID)
            try restoreTaskQuantityEntries(context: context, now: now, deviceID: deviceID)
            try restoreSessions(context: context, now: now, deviceID: deviceID)
            try restoreSegments(context: context, now: now, deviceID: deviceID)
            try restorePomodoroRuns(context: context, now: now, deviceID: deviceID)
            try restoreCountdownEvents(context: context, now: now, deviceID: deviceID)
            try restoreSyncedPreferences(context: context, now: now, deviceID: deviceID)
            try restoreChecklistItems(context: context, now: now, deviceID: deviceID)
            try restoreChecklistItemVisuals(context: context, now: now, deviceID: deviceID)
            try restoreInboxItems(context: context, now: now, deviceID: deviceID)
            try restoreInboxSuggestions(context: context, now: now, deviceID: deviceID)
            try restoreInboxCaptureReceipts(context: context, now: now, deviceID: deviceID)
        }
    }
}
