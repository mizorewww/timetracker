import Foundation
import Testing
@testable import timetracker

@MainActor
struct TaskDetailAutosaveControllerTests {
    private func request(isValid: Bool = true) -> TaskDetailAutosaveRequest {
        var draft = TaskEditorDraft(parentID: nil)
        draft.title = "Edited"
        return TaskDetailAutosaveRequest(
            isEnabled: true,
            draft: draft,
            hasUnsavedChanges: true,
            isValid: isValid
        )
    }

    @Test
    func aSavedEditLeavesNothingToReport() {
        let controller = TaskDetailAutosaveController { _ in .saved }

        #expect(controller.flush(request()))
        #expect(controller.unsavedChangesMessage == nil)
    }

    @Test
    func aFailedSaveExplainsWhyTheEditIsNotSaved() {
        let controller = TaskDetailAutosaveController { _ in .failed(message: "Disk full") }

        #expect(controller.flush(request()) == false)
        #expect(controller.unsavedChangesMessage == "Disk full")
    }

    @Test
    func anInvalidOrConflictedEditIsReportedAsNotSaved() {
        var commits = 0
        let invalid = TaskDetailAutosaveController { _ in
            commits += 1
            return .saved
        }
        #expect(invalid.flush(request(isValid: false)) == false)
        #expect(invalid.unsavedChangesMessage != nil)
        #expect(commits == 0)

        let conflicted = TaskDetailAutosaveController { _ in .conflicted }
        #expect(conflicted.flush(request()) == false)
        #expect(conflicted.unsavedChangesMessage != nil)
    }
}
