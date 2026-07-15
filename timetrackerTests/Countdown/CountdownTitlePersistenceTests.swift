import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct CountdownTitlePersistenceTests {
    @Test @MainActor
    func titlePolicyUsesTheSnapshotUTF8LimitAndRejectsInvalidText() throws {
        #expect(
            CountdownTitlePolicy.maximumUTF8ByteCount
                == SyncDataSnapshotRestoreLimits.maximumTitleByteCount
        )

        let exactLimitTitle = String(repeating: "🙂", count: 1_024)
        #expect(exactLimitTitle.utf8.count == 4_096)
        #expect(try CountdownTitlePolicy.normalized("  \(exactLimitTitle)  ") == exactLimitTitle)

        #expect(throws: CountdownTitleValidationError.empty) {
            try CountdownTitlePolicy.normalized(" \n\t ")
        }
        #expect(throws: CountdownTitleValidationError.exceedsByteLimit) {
            try CountdownTitlePolicy.normalized(exactLimitTitle + "a")
        }
        #expect(throws: CountdownTitleValidationError.containsControlCharacters) {
            try CountdownTitlePolicy.normalized("Launch\u{2028}Day")
        }
        #expect(throws: CountdownTitleValidationError.containsControlCharacters) {
            try CountdownTitlePolicy.normalized("Launch\u{0000}Day")
        }
    }

    @Test @MainActor
    func commandRejectsInvalidTitleBeforeMutatingAnyEventField() throws {
        let context = try makeTestContext()
        let event = CountdownEvent(
            title: "Original",
            date: Date(timeIntervalSince1970: 10_000),
            deviceID: "original-device"
        )
        context.insert(event)
        try context.save()

        let originalDate = event.date
        let originalUpdatedAt = event.updatedAt
        let originalMutationID = event.clientMutationID
        let replacementDate = Date(timeIntervalSince1970: 20_000)

        #expect(throws: CountdownTitleValidationError.empty) {
            try CountdownCommandHandler().update(
                event,
                title: "   ",
                date: replacementDate,
                context: context,
                now: Date(timeIntervalSince1970: 30_000)
            )
        }

        #expect(event.title == "Original")
        #expect(event.date == originalDate)
        #expect(event.updatedAt == originalUpdatedAt)
        #expect(event.clientMutationID == originalMutationID)
    }

    @Test @MainActor
    func storeReturnsFailureForAnInvalidTitleWithoutChangingTheModel() throws {
        let context = try makeTestContext()
        let event = CountdownEvent(
            title: "Original",
            date: Date(timeIntervalSince1970: 10_000),
            deviceID: "test"
        )
        context.insert(event)
        try context.save()

        let store = TimeTrackerStore()
        store.modelContext = context
        store.countdownEvents = [event]
        let originalUpdatedAt = event.updatedAt
        let originalMutationID = event.clientMutationID

        let didSave = store.updateCountdownEvent(event, title: "\n")

        #expect(!didSave)
        #expect(event.title == "Original")
        #expect(event.updatedAt == originalUpdatedAt)
        #expect(event.clientMutationID == originalMutationID)
        #expect(store.errorMessage == CountdownTitleValidationError.empty.localizedDescription)
    }

    @Test @MainActor
    func repeatedTypingDoesNotSaveAndOneCommitSavesOnce() {
        var draft = CountdownTitleDraft(persistedTitle: "Launch")
        var savedTitles: [String] = []

        draft.text = "Launch D"
        draft.text = "Launch Da"
        draft.text = "  Launch Day  "
        #expect(savedTitles.isEmpty)

        #expect(draft.commit { title in
            savedTitles.append(title)
            return true
        })
        #expect(savedTitles == ["Launch Day"])
        #expect(draft.text == "Launch Day")
        #expect(!draft.isDirty)

        #expect(draft.commit { title in
            savedTitles.append(title)
            return true
        })
        #expect(savedTitles == ["Launch Day"])
    }

    @Test @MainActor
    func validationAndSaveFailuresKeepTheDraftForCorrectionOrRetry() {
        var draft = CountdownTitleDraft(persistedTitle: "Launch")
        var saveAttempts: [String] = []

        draft.text = "   "
        #expect(!draft.commit { title in
            saveAttempts.append(title)
            return true
        })
        #expect(saveAttempts.isEmpty)
        #expect(draft.text == "   ")
        #expect(draft.error == .validation(.empty))

        draft.text = "  Renamed Launch  "
        #expect(!draft.commit { title in
            saveAttempts.append(title)
            return false
        })
        #expect(saveAttempts == ["Renamed Launch"])
        #expect(draft.text == "  Renamed Launch  ")
        #expect(draft.isDirty)
        #expect(draft.error == .saveFailed)

        #expect(draft.commit { title in
            saveAttempts.append(title)
            return true
        })
        #expect(saveAttempts == ["Renamed Launch", "Renamed Launch"])
        #expect(draft.text == "Renamed Launch")
        #expect(!draft.isDirty)
        #expect(draft.error == nil)
    }

    @Test @MainActor
    func externalRefreshDoesNotOverwriteAnUnsavedDraft() {
        var draft = CountdownTitleDraft(persistedTitle: "Launch")
        draft.text = "My Draft"

        draft.reconcile(persistedTitle: "Remote Rename")

        #expect(draft.text == "My Draft")
        #expect(draft.isDirty)
    }
}
