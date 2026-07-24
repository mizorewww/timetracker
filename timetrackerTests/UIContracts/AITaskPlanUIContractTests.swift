import Foundation
import Testing

@Suite(.serialized)
struct AITaskPlanUIContractTests {
    @Test
    func tasksMenuRoutesToOneDraftFirstGeneratorSheet() throws {
        let tasks = try sourceText(
            "timetracker/Features/Tasks/Management/TasksViews.swift"
        )
        let generator = try sourceText(
            "timetracker/Features/Tasks/Generation/AITaskPlanGeneratorViews.swift"
        )
        let host = try sourceText("timetracker/App/AppPresentationHost.swift")

        #expect(tasks.contains("presentationRouter.presentAITaskPlanGenerator()"))
        #expect(tasks.contains(".sheet(") == false)
        #expect(generator.contains("Form {"))
        #expect(generator.contains("List {"))
        #expect(generator.contains("AITaskPlanDraftPreview"))
        #expect(generator.contains("onCreate: (AITaskPlanDraft)"))
        #expect(generator.contains("store.saveAITaskPlan") == false)
        #expect(generator.contains("TextField("))
        #expect(generator.contains("removeTaskSubtree"))
        #expect(generator.contains("pruningUnusedCategories"))
        #expect(generator.contains("AITaskPlanTaskProgressDraftEditor"))
        #expect(generator.contains("TaskProgressDraftPersistencePolicy.prepare"))
        #expect(generator.contains(".quantity.toggle"))
        #expect(generator.contains(".quantity.target"))
        #expect(generator.contains(".quantity.unit"))
        #expect(generator.contains(".recurrence.daily"))
        #expect(generator.contains("quantityGoal: TaskQuantityGoalDraft("))
        #expect(generator.contains("dailyRecurrence: TaskDailyRecurrenceDraft("))
        #expect(generator.contains("checklistItems: (1...10).map"))
        #expect(generator.contains(".editorDiscardConfirmation("))
        #expect(generator.contains("hasUnsavedChanges: hasUnsavedChanges || isCreating"))
        #expect(generator.contains("pendingDiscardAction = .returnToRequest"))
        #expect(host.contains("store.saveAITaskPlan(draft)"))
    }

    @Test
    func everyEditablePromptUsesOneSafeSettingsEditorAndPreservesFixedRules() throws {
        let settings = try sourceText(
            "timetracker/Features/Settings/LLMSettingsSection.swift"
        )
        let editor = try sourceText(
            "timetracker/Features/Settings/LLMPromptInstructionsEditor.swift"
        )
        let service = try sourceText(
            "timetracker/Services/LLM/LLMTaskPlanService.swift"
        )

        #expect(settings.contains("ForEach(LLMPromptKind.allCases)"))
        #expect(settings.contains("onEditPrompt(kind)"))
        #expect(editor.contains("TextEditor(text: $draft)"))
        #expect(editor.contains("import MarkdownView"))
        #expect(editor.contains("kind == .taskPlan") == false)
        #expect(editor.contains("MarkdownView(draft)"))
        #expect(editor.contains(".pickerStyle(.segmented)"))
        #expect(editor.contains(#"\(accessibilityID).mode"#))
        #expect(editor.contains(#"\(accessibilityID).preview"#))
        #expect(editor.contains("maximumLLMPromptInstructionsByteCount"))
        #expect(editor.contains("llmPromptInstructions(draft, for: kind)"))
        #expect(editor.contains("restoreDefault"))
        #expect(editor.contains("kind.defaultInstructions"))
        #expect(editor.contains("kind.fixedResponseContract"))
        #expect(editor.contains("SymbolCatalog.aiSuggestionSymbolNames"))
        #expect(editor.contains("TaskColorPalette.hexValues"))
        #expect(editor.contains(#"\(accessibilityID).fixedRules"#))
        #expect(editor.contains(#"\(accessibilityID).allowedVisuals"#))
        #expect(editor.contains(".editorDiscardConfirmation("))
        #expect(editor.contains(".navigationBarBackButtonHidden(isEmbeddedInNavigationStack)"))
        #expect(service.contains("systemContract"))
        #expect(service.contains("instructions: preparedInstructions"))
        #expect(service.contains("maximumTaskDepth = 6"))
        #expect(service.contains("at most 8 categories, 64 tasks"))
    }

    @Test
    func everyMainLocaleContainsAllPromptSurfacesAndTaskPlanRecoveryCopy() throws {
        let requiredKeys = [
            "aiTaskPlan.title",
            "aiTaskPlan.request.footer",
            "aiTaskPlan.preview.footer",
            "settings.llm.taskPlan.error.invalidResponse",
            "settings.llm.taskPlan.error.identityConflict",
            "settings.llm.prompt.inboxRouting.title",
            "settings.llm.prompt.inboxRouting.edit",
            "settings.llm.prompt.inboxRouting.editorTitle",
            "settings.llm.prompt.inboxRouting.footer",
            "settings.llm.prompt.checklistVisual.title",
            "settings.llm.prompt.checklistVisual.edit",
            "settings.llm.prompt.checklistVisual.editorTitle",
            "settings.llm.prompt.checklistVisual.footer",
            "settings.llm.prompt.taskPlan.title",
            "settings.llm.prompt.taskPlan.edit",
            "settings.llm.prompt.taskPlan.editorTitle",
            "settings.llm.prompt.taskPlan.footer",
            "settings.llm.prompt.restoreDefault",
            "settings.llm.prompt.byteCountFormat",
            "settings.llm.prompt.footer",
            "settings.llm.prompt.contractSection",
            "settings.llm.prompt.fixedRules",
            "settings.llm.prompt.allowedVisuals",
            "settings.llm.prompt.error.controlCharacter",
            "settings.llm.prompt.error.tooLongFormat",
            "task.notes.preview",
            "task.quantity.editor.toggle",
            "task.quantity.editor.target",
            "task.quantity.editor.unit",
            "task.recurrence.editor.daily",
        ]

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let strings = try sourceText(
                "timetracker/\(locale).lproj/Localizable.strings"
            )
            for key in requiredKeys {
                #expect(
                    strings.contains("\"\(key)\" ="),
                    "Missing \(key) in \(locale)"
                )
            }
        }
    }
}
