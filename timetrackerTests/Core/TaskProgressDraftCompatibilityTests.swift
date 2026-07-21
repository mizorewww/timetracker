import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskProgressDraftCompatibilityTests {
    @Test
    func legacyRecoveryPayloadWithoutProgressFieldsStillDecodes()
        throws {
        let taskID = UUID()
        var draft = TaskEditorDraft(parentID: nil)
        draft.taskID = taskID
        draft.title = "Legacy draft"
        draft.baseline = TaskEditorDraftBaseline(
            taskMutationID: UUID(),
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDs: [:],
            categoryAssignmentMutationID: nil,
            quantityGoalMutationID: UUID(),
            recurrenceRuleMutationID: UUID()
        )
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        let envelope = TaskDraftRecoveryEnvelope(
            schemaVersion: 1,
            sourceTaskID: taskID,
            savedAt: Date(timeIntervalSince1970: 1_000),
            draft: draft
        )
        let encoded = try TaskDraftRecoveryCodec.encode(envelope)
        var root = try #require(
            JSONSerialization.jsonObject(with: encoded) as?
                [String: Any]
        )
        var legacyDraft = try #require(
            root["draft"] as? [String: Any]
        )
        legacyDraft.removeValue(forKey: "quantityGoal")
        legacyDraft.removeValue(forKey: "dailyRecurrence")
        legacyDraft.removeValue(
            forKey: "confirmsQuantityProgressReset"
        )
        var legacyBaseline = try #require(
            legacyDraft["baseline"] as? [String: Any]
        )
        legacyBaseline.removeValue(forKey: "quantityGoalMutationID")
        legacyBaseline.removeValue(forKey: "recurrenceRuleMutationID")
        legacyBaseline.removeValue(forKey: "quantityEntryRevision")
        legacyDraft["baseline"] = legacyBaseline
        root["draft"] = legacyDraft

        let decoded = try TaskDraftRecoveryCodec.decode(
            JSONSerialization.data(withJSONObject: root)
        )

        #expect(decoded.draft.title == "Legacy draft")
        #expect(decoded.draft.quantityGoal == nil)
        #expect(decoded.draft.dailyRecurrence == nil)
        #expect(decoded.draft.confirmsQuantityProgressReset == false)
        #expect(decoded.draft.baseline?.quantityGoalMutationID == nil)
        #expect(decoded.draft.baseline?.recurrenceRuleMutationID == nil)
        #expect(decoded.draft.baseline?.quantityEntryRevision == nil)
    }

    @Test
    func recoveryComparisonIncludesQuantityAndRecurrenceContent() {
        var original = TaskEditorDraft(parentID: nil)
        original.title = "Push-ups"
        original.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        original.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        var changed = original

        #expect(
            TaskDraftRecoveryCodec.hasSameRecoverableContent(
                original,
                changed
            )
        )
        changed.quantityGoal?.targetAmount = 75
        #expect(
            TaskDraftRecoveryCodec.hasSameRecoverableContent(
                original,
                changed
            ) == false
        )
        changed = original
        changed.dailyRecurrence?.isEnabled = false
        #expect(
            TaskDraftRecoveryCodec.hasSameRecoverableContent(
                original,
                changed
            ) == false
        )
    }

    @Test
    func currentRecoveryRoundTripDropsDestructiveAuthorization()
        throws {
        let taskID = UUID()
        let entryRevision = UUID()
        var draft = TaskEditorDraft(parentID: nil)
        draft.taskID = taskID
        draft.title = "Daily push-ups"
        draft.baseline = TaskEditorDraftBaseline(
            taskMutationID: UUID(),
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDs: [:],
            categoryAssignmentMutationID: nil,
            quantityGoalMutationID: UUID(),
            recurrenceRuleMutationID: UUID(),
            quantityEntryRevision: entryRevision
        )
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )
        draft.confirmsQuantityProgressReset = true
        let envelope = TaskDraftRecoveryEnvelope(
            schemaVersion: 1,
            sourceTaskID: taskID,
            savedAt: Date(timeIntervalSince1970: 2_000),
            draft: draft
        )

        let decoded = try TaskDraftRecoveryCodec.decode(
            TaskDraftRecoveryCodec.encode(envelope)
        )

        #expect(decoded.draft.quantityGoal == draft.quantityGoal)
        #expect(decoded.draft.dailyRecurrence == draft.dailyRecurrence)
        #expect(
            decoded.draft.baseline?.quantityEntryRevision ==
                entryRevision
        )
        #expect(decoded.draft.confirmsQuantityProgressReset == false)
    }

    @Test
    func recoveryCopyPreservesProgressConfigurationWithoutIdentity() {
        var draft = TaskEditorDraft(parentID: nil)
        draft.taskID = UUID()
        draft.baseline = TaskEditorDraftBaseline(
            taskMutationID: UUID(),
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDs: [:],
            categoryAssignmentMutationID: nil,
            quantityGoalMutationID: UUID(),
            recurrenceRuleMutationID: UUID()
        )
        draft.quantityGoal = TaskQuantityGoalDraft(
            targetAmount: 50,
            unitLabel: "reps"
        )
        draft.dailyRecurrence = TaskDailyRecurrenceDraft(
            startDayKey: "2026-07-21",
            timeZoneIdentifier: "Asia/Singapore"
        )

        let copy = draft.copyAsNew(parentID: nil, categoryID: nil)

        #expect(copy.taskID == nil)
        #expect(copy.baseline == nil)
        #expect(copy.quantityGoal == draft.quantityGoal)
        #expect(copy.confirmsQuantityProgressReset == false)
        #expect(copy.dailyRecurrence == draft.dailyRecurrence)
    }

    @Test
    func persistencePolicyRejectsEveryInvalidProgressBoundary() {
        #expect(throws: TaskProgressDraftMutationError.invalidTargetAmount) {
            try TaskProgressDraftPersistencePolicy.prepare(
                quantityGoal: TaskQuantityGoalDraft(
                    targetAmount: TaskQuantityPolicy.valueRange.upperBound + 1,
                    unitLabel: "reps"
                ),
                dailyRecurrence: nil
            )
        }
        #expect(throws: TaskProgressDraftMutationError.unitRequired) {
            try TaskProgressDraftPersistencePolicy.prepare(
                quantityGoal: TaskQuantityGoalDraft(
                    targetAmount: 50,
                    unitLabel: "  \n"
                ),
                dailyRecurrence: nil
            )
        }
        #expect(
            throws: TaskProgressDraftMutationError
                .unitContainsControlCharacter
        ) {
            try TaskProgressDraftPersistencePolicy.prepare(
                quantityGoal: TaskQuantityGoalDraft(
                    targetAmount: 50,
                    unitLabel: "reps\u{0000}"
                ),
                dailyRecurrence: nil
            )
        }
        #expect(
            throws: TaskProgressDraftMutationError
                .unitByteLimitExceeded(
                    actual: 129,
                    maximum:
                        TaskQuantityPolicy.maximumUnitLabelByteCount
                )
        ) {
            try TaskProgressDraftPersistencePolicy.prepare(
                quantityGoal: TaskQuantityGoalDraft(
                    targetAmount: 50,
                    unitLabel: String(repeating: "x", count: 129)
                ),
                dailyRecurrence: nil
            )
        }
        #expect(throws: TaskRecurrenceMutationError.invalidStartDay) {
            try TaskProgressDraftPersistencePolicy.prepare(
                quantityGoal: nil,
                dailyRecurrence: TaskDailyRecurrenceDraft(
                    startDayKey: "2026-02-30",
                    timeZoneIdentifier: "Asia/Singapore"
                )
            )
        }
        #expect(throws: TaskRecurrenceMutationError.invalidTimeZone) {
            try TaskProgressDraftPersistencePolicy.prepare(
                quantityGoal: nil,
                dailyRecurrence: TaskDailyRecurrenceDraft(
                    startDayKey: "2026-07-21",
                    timeZoneIdentifier: "Mars/Olympus"
                )
            )
        }
    }
}
