import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
@MainActor
struct TaskDetailAutosaveControllerTests {
    @Test
    func rapidDraftChangesCommitOnlyTheLatestRequest() async {
        var committedTitles: [String] = []
        let controller = TaskDetailAutosaveController(
            delay: .milliseconds(20)
        ) { draft in
            committedTitles.append(draft.title)
            return .saved
        }
        var first = TaskEditorDraft(parentID: nil)
        first.title = "First"
        var latest = first
        latest.title = "Latest"

        controller.update(with: request(for: first))
        controller.update(with: request(for: latest))
        await waitUntil(timeout: .seconds(5)) {
            controller.status == .saved
        }

        #expect(committedTitles == ["Latest"])
        #expect(controller.status == .saved)
    }

    @Test
    func navigationFlushCommitsTheLatestDraftAndCancelsItsDebounce() async {
        var committedTitles: [String] = []
        let controller = TaskDetailAutosaveController(
            delay: .milliseconds(30)
        ) { draft in
            committedTitles.append(draft.title)
            return .saved
        }
        var scheduled = TaskEditorDraft(parentID: nil)
        scheduled.title = "Scheduled"
        var latest = scheduled
        latest.title = "Flush this"

        controller.update(with: request(for: scheduled))
        let didSave = controller.flush(request(for: latest))
        try? await Task.sleep(for: .milliseconds(80))

        #expect(didSave)
        #expect(committedTitles == ["Flush this"])
    }

    @Test
    func invalidDraftWaitsForCorrectionWithoutCallingPersistence() {
        var commitCount = 0
        let controller = TaskDetailAutosaveController { _ in
            commitCount += 1
            return .saved
        }
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = ""

        controller.update(
            with: request(for: draft, isValid: false)
        )

        #expect(controller.flush() == false)
        #expect(controller.status == .validationBlocked)
        #expect(commitCount == 0)

        draft.title = "Valid"
        #expect(controller.flush(request(for: draft)))
        #expect(commitCount == 1)
    }

    @Test
    func failedSaveKeepsRetryableStateUntilACommitSucceeds() {
        var attempts = 0
        let controller = TaskDetailAutosaveController { _ in
            attempts += 1
            return attempts == 1
                ? .failed(message: "Disk full")
                : .saved
        }
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Keep this"
        let pending = request(for: draft)

        #expect(controller.flush(pending) == false)
        #expect(controller.status == .failed(message: "Disk full"))
        #expect(controller.retry())
        #expect(controller.status == .saved)
        #expect(attempts == 2)
    }

    @Test
    func conflictNeverReportsACompletedFlush() {
        let controller = TaskDetailAutosaveController { _ in
            .conflicted
        }
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Preserve this"

        #expect(controller.flush(request(for: draft)) == false)
        #expect(controller.status == .conflicted)
    }

    private func request(
        for draft: TaskEditorDraft,
        isValid: Bool = true
    ) -> TaskDetailAutosaveRequest {
        TaskDetailAutosaveRequest(
            isEnabled: true,
            draft: draft,
            hasUnsavedChanges: true,
            isValid: isValid
        )
    }

    private func waitUntil(
        timeout: Duration,
        condition: () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)
        while condition() == false, clock.now < deadline {
            try? await Task.sleep(for: .milliseconds(10))
            await Task.yield()
        }
    }
}
