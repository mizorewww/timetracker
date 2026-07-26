import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreAppPresentationRouterTests {
    @Test @MainActor
    func busyRouterRejectsASecondRequestAndPreservesThePresentedIdentity() throws {
        let router = AppPresentationRouter()

        #expect(router.present(.startTaskPicker))
        let firstPresentation = try #require(router.sheet)

        #expect(router.present(.quickStartEditor(selectedIDs: [UUID()])) == false)
        #expect(router.sheet?.id == firstPresentation.id)
        guard case .startTaskPicker = try #require(router.sheet).content else {
            Issue.record("The busy router replaced its current presentation.")
            return
        }
    }

    @Test @MainActor
    func matchingReplacementAtomicallySwapsTheCurrentPresentation() throws {
        let router = AppPresentationRouter()
        #expect(router.present(.startTaskPicker))
        let pickerID = try #require(router.sheet?.id)
        let selectedIDs = [UUID(), UUID()]

        #expect(router.replace(
            presentationID: pickerID,
            with: .quickStartEditor(selectedIDs: selectedIDs)
        ))

        let replacement = try #require(router.sheet)
        #expect(replacement.id != pickerID)
        guard case let .quickStartEditor(replacementIDs) = replacement.content else {
            Issue.record("The replacement did not install the requested presentation.")
            return
        }
        #expect(replacementIDs == selectedIDs)
    }

    @Test @MainActor
    func staleReplacementAndDismissalCannotMutateANewerPresentation() throws {
        let router = AppPresentationRouter()
        #expect(router.present(.startTaskPicker))
        let pickerID = try #require(router.sheet?.id)
        #expect(router.replace(
            presentationID: pickerID,
            with: .quickStartEditor(selectedIDs: [])
        ))
        let replacementID = try #require(router.sheet?.id)

        #expect(router.replace(
            presentationID: pickerID,
            with: .llmConfiguration(LLMConfigurationDraft(
                endpoint: "https://example.com",
                apiKey: "key",
                selectedModel: "model",
                availableModels: ["model"],
                reasoningEffort: .high
            ))
        ) == false)
        router.dismiss(presentationID: pickerID)

        #expect(router.sheet?.id == replacementID)
        guard case .quickStartEditor = try #require(router.sheet).content else {
            Issue.record("A stale callback mutated the newer presentation.")
            return
        }
    }

    @Test @MainActor
    func matchingDismissalClearsTheCurrentPresentation() throws {
        let router = AppPresentationRouter()
        #expect(router.present(.startTaskPicker))
        let presentationID = try #require(router.sheet?.id)

        router.dismiss(presentationID: presentationID)

        #expect(router.sheet == nil)
    }

    @Test @MainActor
    func settingsUsesTheTypedScenePresentationRoute() throws {
        let router = AppPresentationRouter()

        #expect(router.presentSettings())

        guard case .settings = try #require(router.sheet).content else {
            Issue.record("Settings did not use the scene presentation route.")
            return
        }
    }

    @Test @MainActor
    func taskPlanGeneratorUsesTheTypedScenePresentationRoute() throws {
        let router = AppPresentationRouter()

        #expect(router.presentAITaskPlanGenerator())

        guard case .aiTaskPlanGenerator = try #require(router.sheet).content else {
            Issue.record("Task plan generation did not use the scene presentation route.")
            return
        }
    }

    @Test @MainActor
    func pomodoroTaskPickerKeepsItsSelectionCallbackInTheOwningScene() throws {
        let router = AppPresentationRouter()
        let selectedBeforePresenting = UUID()
        let selectedFromPicker = UUID()
        var receivedSelection: UUID?

        #expect(router.presentPomodoroTaskPicker(
            selectedTaskID: selectedBeforePresenting,
            selectTask: { receivedSelection = $0 }
        ))

        let presentation = try #require(router.sheet)
        guard case let .singleTaskPicker(picker) = presentation.content else {
            Issue.record("Focus did not use its typed scene picker route.")
            return
        }
        #expect(picker.selectedTaskID == selectedBeforePresenting)
        #expect(picker.context == .pomodoro)

        #expect(picker.selectTask(selectedFromPicker))
        #expect(receivedSelection == selectedFromPicker)
        #expect(router.sheet?.id == presentation.id)

        router.dismiss(presentationID: presentation.id)
        #expect(router.sheet == nil)
    }

    @Test @MainActor
    func genericTaskPickerPreservesContextAndReportsRejectedSelections() throws {
        let router = AppPresentationRouter()
        let attemptedTaskID = UUID()

        #expect(router.presentSingleTaskPicker(
            selectedTaskID: nil,
            context: .inboxChecklistTarget,
            selectTask: { _ in false }
        ))

        let presentation = try #require(router.sheet)
        guard case let .singleTaskPicker(picker) = presentation.content else {
            Issue.record("Inbox did not use the generic task-picker route.")
            return
        }
        #expect(picker.context == .inboxChecklistTarget)
        #expect(picker.selectTask(attemptedTaskID) == false)
        #expect(router.sheet?.id == presentation.id)
    }

    @Test @MainActor
    func categoryPickerPreservesContextAndReportsRejectedSelections() throws {
        let router = AppPresentationRouter()
        let attemptedCategoryID = UUID()

        #expect(router.presentSingleTaskCategoryPicker(
            selectedCategoryID: nil,
            context: .inboxTaskDestination,
            selectCategory: { _ in false }
        ))

        let presentation = try #require(router.sheet)
        guard case let .singleTaskCategoryPicker(picker) = presentation.content else {
            Issue.record("Inbox did not use the typed category-picker route.")
            return
        }
        #expect(picker.context == .inboxTaskDestination)
        #expect(picker.selectCategory(attemptedCategoryID) == false)
        #expect(router.sheet?.id == presentation.id)
    }

    @Test @MainActor
    func separateSceneRoutersDoNotSharePresentationState() throws {
        let mainSceneRouter = AppPresentationRouter()
        let settingsSceneRouter = AppPresentationRouter()

        #expect(mainSceneRouter.present(.startTaskPicker))
        #expect(settingsSceneRouter.present(.manualTime(ManualTimeDraft(taskID: nil, tasks: []))))

        let mainPresentationID = try #require(mainSceneRouter.sheet?.id)
        let settingsPresentationID = try #require(settingsSceneRouter.sheet?.id)
        #expect(mainPresentationID != settingsPresentationID)

        mainSceneRouter.dismiss(presentationID: mainPresentationID)
        #expect(mainSceneRouter.sheet == nil)
        #expect(settingsSceneRouter.sheet?.id == settingsPresentationID)
    }

    @Test @MainActor
    func taskPickerCanAtomicallyReplaceItselfWithANewTaskEditor() throws {
        let store = makeTestStore()
        store.desktopDestination = .tasks
        let router = AppPresentationRouter()
        #expect(router.presentStartTaskPicker())
        let pickerID = try #require(router.sheet?.id)

        #expect(router.replaceWithNewTask(
            presentationID: pickerID,
            using: store,
            preservingDestination: .tasks
        ))

        let replacement = try #require(router.sheet)
        #expect(replacement.id != pickerID)
        guard case let .taskEditor(draft, returnDestination) = replacement.content else {
            Issue.record("The task picker did not transition to the task editor.")
            return
        }
        #expect(draft.taskID == nil)
        #expect(draft.parentID == nil)
        #expect(returnDestination == .tasks)
    }

    @Test @MainActor
    func invalidPresentationRequestDoesNotCloseTheCurrentSheet() throws {
        let unavailableParent = TaskNode(
            title: "Archived parent",
            parentID: nil,
            deviceID: "test"
        )
        unavailableParent.statusRaw = LegacyTaskStatusRaw.archived
        let store = makeTestStore()
        store.tasks = [unavailableParent]
        let router = AppPresentationRouter()
        #expect(router.presentStartTaskPicker())
        let pickerID = try #require(router.sheet?.id)

        #expect(router.presentNewTask(
            using: store,
            parentID: unavailableParent.id,
            preservingDestination: .tasks
        ) == false)

        #expect(store.errorMessage == AppStrings.localized("task.parentUnavailable"))
        #expect(router.sheet?.id == pickerID)
        guard case .startTaskPicker = try #require(router.sheet).content else {
            Issue.record("A failed request dismissed or replaced the current sheet.")
            return
        }
    }

    @Test @MainActor
    func failedStoreCommitLeavesTheScenePresentationOpen() throws {
        let task = TaskNode(title: "Manual time", parentID: nil, deviceID: "test")
        let store = makeTestStore()
        store.tasks = [task]
        let router = AppPresentationRouter()
        #expect(router.presentManualTime(taskID: task.id, using: store))
        let presentation = try #require(router.sheet)
        guard case var .manualTime(draft) = presentation.content else {
            Issue.record("Expected a manual-time presentation.")
            return
        }
        draft.startedAt = Date().addingTimeInterval(-600)
        draft.endedAt = Date()

        #expect(store.saveManualTimeDraft(draft) == false)
        #expect(store.errorMessage != nil)
        #expect(router.sheet?.id == presentation.id)
    }
}
