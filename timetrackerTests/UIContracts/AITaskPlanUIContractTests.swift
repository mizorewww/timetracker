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
        #expect(generator.contains(".editorDiscardConfirmation("))
        #expect(generator.contains("hasUnsavedChanges: hasUnsavedChanges || isCreating"))
        #expect(generator.contains("pendingDiscardAction = .returnToRequest"))
        #expect(host.contains("store.saveAITaskPlan(draft)"))
    }

    @Test
    func editablePlanningInstructionsStayInSettingsAndPreserveFixedRules() throws {
        let settings = try sourceText(
            "timetracker/Features/Settings/LLMSettingsSection.swift"
        )
        let editor = try sourceText(
            "timetracker/Features/Settings/LLMTaskPlanInstructionsEditor.swift"
        )
        let service = try sourceText(
            "timetracker/Services/LLM/LLMTaskPlanService.swift"
        )

        #expect(settings.contains("onEditTaskPlanInstructions"))
        #expect(editor.contains("TextEditor(text: $draft)"))
        #expect(editor.contains("maximumLLMTaskPlanInstructionsByteCount"))
        #expect(editor.contains("restoreDefault"))
        #expect(service.contains("systemContract"))
        #expect(service.contains("instructions: preparedInstructions"))
        #expect(service.contains("maximumTaskDepth = 6"))
        #expect(service.contains("at most 8 categories, 64 tasks"))
    }

    @Test
    func everyMainLocaleContainsTaskPlanSurfaceAndRecoveryCopy() throws {
        let requiredKeys = [
            "aiTaskPlan.title",
            "aiTaskPlan.request.footer",
            "aiTaskPlan.preview.footer",
            "settings.llm.taskPlan.error.invalidResponse",
            "settings.llm.taskPlan.error.identityConflict",
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
