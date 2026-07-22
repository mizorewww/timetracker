import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLLMChecklistRequestBudgetTests {
    @Test
    func checklistPromptUsesCuratedSymbolsAndBoundedUTF8Fields() throws {
        let customInstructions = "Prefer a calm color and a literal symbol."
        let request = try LLMChecklistVisualSuggestionService().suggestionRequest(
            checklistTitle: String(repeating: "  \"检查细节🧩\\  ", count: 400),
            taskTitle: String(repeating: "  \"产品设计🎨\\  ", count: 400),
            taskPath: String(repeating: "  Root/项目/\"设计🚀\\  ", count: 500),
            instructions: customInstructions,
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: String(repeating: "模型🧪", count: 300)
        )
        let body = try #require(request.httpBody)
        let envelope = try JSONDecoder().decode(ChecklistRequestEnvelope.self, from: body)
        let userMessage = try #require(envelope.messages.last { $0.role == "user" })
        let prompt = try JSONDecoder().decode(
            ChecklistPromptEnvelope.self,
            from: Data(userMessage.content.utf8)
        )
        let excludedSymbol = try #require(
            SymbolCatalog.symbolNames.first {
                !SymbolCatalog.aiSuggestionSymbolNameSet.contains($0)
            }
        )
        let systemMessage = try #require(envelope.messages.first { $0.role == "system" })

        #expect(prompt.instructions == customInstructions)
        #expect(systemMessage.content.contains("iconName, colorHex, reason"))
        #expect(systemMessage.content.contains("allowedSymbols"))
        #expect(body.count <= LLMSuggestionInputPolicy.maximumRequestBodyByteCount)
        #expect(userMessage.content.utf8.count <= LLMSuggestionInputPolicy.maximumPromptByteCount)
        #expect(envelope.model.utf8.count <= LLMSuggestionInputPolicy.maximumModelIDByteCount)
        #expect(prompt.checklistTitle.utf8.count <= LLMSuggestionInputPolicy.maximumChecklistTitleByteCount)
        #expect(prompt.taskTitle.utf8.count <= LLMSuggestionInputPolicy.maximumTaskTitleByteCount)
        #expect(prompt.taskPath.utf8.count <= LLMSuggestionInputPolicy.maximumTaskPathByteCount)
        #expect(prompt.allowedSymbols == SymbolCatalog.aiSuggestionSymbolNames)
        #expect(!prompt.allowedSymbols.contains(excludedSymbol))
    }

    @Test
    func maximumEditableChecklistInstructionsStayWithinRequestBudgets() throws {
        let instructions = String(
            repeating: "\\\"",
            count: AppPreferenceValueSanitizer.maximumLLMPromptInstructionsByteCount / 2
        )
        let request = try LLMChecklistVisualSuggestionService().suggestionRequest(
            checklistTitle: String(repeating: "\\\"", count: 400),
            taskTitle: String(repeating: "\\\"", count: 400),
            taskPath: String(repeating: "Root/\\\"", count: 300),
            instructions: instructions,
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "test-model"
        )
        let body = try #require(request.httpBody)
        let envelope = try JSONDecoder().decode(ChecklistRequestEnvelope.self, from: body)
        let userMessage = try #require(envelope.messages.last { $0.role == "user" })
        let prompt = try JSONDecoder().decode(
            ChecklistPromptEnvelope.self,
            from: Data(userMessage.content.utf8)
        )

        #expect(prompt.instructions == instructions)
        #expect(body.count <= LLMSuggestionInputPolicy.maximumRequestBodyByteCount)
        #expect(userMessage.content.utf8.count <= LLMSuggestionInputPolicy.maximumPromptByteCount)
    }

    @Test
    func checklistResponseFieldsAreBoundedToAdvertisedValues() {
        let result = LLMChecklistVisualSuggestionService.sanitize(
            payload: ChecklistVisualSuggestionPayload(
                iconName: String(repeating: "trash", count: 100),
                colorHex: String(repeating: "#007AFF", count: 100),
                reason: String(repeating: "理由🧩", count: 400)
            ),
            modelID: String(repeating: "模型🧪", count: 300)
        )

        #expect(result.iconName == ChecklistVisualSanitizer.defaultIcon)
        #expect(result.colorHex == ChecklistVisualSanitizer.defaultColor)
        #expect(result.reason.utf8.count <= LLMSuggestionInputPolicy.maximumReasonByteCount)
        #expect(String(data: Data(result.reason.utf8), encoding: .utf8) == result.reason)
        #expect(result.modelID.utf8.count <= LLMSuggestionInputPolicy.maximumModelIDByteCount)
    }

    @Test
    func persistedModelIDBudgetMatchesSnapshotRestoreContract() throws {
        #expect(
            LLMSuggestionInputPolicy.maximumModelIDByteCount ==
                SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        )
        let exactModelID = String(
            repeating: "m",
            count: LLMSuggestionInputPolicy.maximumModelIDByteCount
        )
        let payload = ChecklistVisualSuggestionPayload(
            iconName: "checkmark.circle",
            colorHex: "1677FF",
            reason: "Matches the task"
        )

        let exactResult = LLMChecklistVisualSuggestionService.sanitize(
            payload: payload,
            modelID: exactModelID
        )
        #expect(exactResult.modelID == exactModelID)

        let boundedResult = LLMChecklistVisualSuggestionService.sanitize(
            payload: payload,
            modelID: exactModelID + "🧪"
        )
        #expect(boundedResult.modelID == exactModelID)
        #expect(
            boundedResult.modelID.utf8.count ==
                SyncDataSnapshotRestoreLimits.maximumCompactFieldByteCount
        )

        let visual = ChecklistItemVisual(
            checklistItemID: UUID(),
            suggestionModelID: boundedResult.modelID,
            deviceID: "test"
        )
        try SyncDataSnapshot(checklistItemVisuals: [ChecklistItemVisualRecord(visual)])
            .validateForRestore()
    }

    @Test
    func checklistRequestRejectsCredentialTextBeyondTheHeaderBudget() {
        #expect(throws: LLMInboxSuggestionServiceError.requestTooLarge) {
            try LLMChecklistVisualSuggestionService().suggestionRequest(
                checklistTitle: "Polish spacing",
                taskTitle: "Design",
                taskPath: "Work / Design",
                endpoint: "https://example.com/v1",
                apiKey: String(
                    repeating: "k",
                    count: LLMSuggestionInputPolicy.maximumAPIKeyByteCount + 1
                ),
                modelID: "test-model"
            )
        }
    }
}

private struct ChecklistRequestEnvelope: Decodable {
    let model: String
    let messages: [Message]

    struct Message: Decodable {
        let role: String
        let content: String
    }
}

private struct ChecklistPromptEnvelope: Decodable {
    let instructions: String
    let checklistTitle: String
    let taskTitle: String
    let taskPath: String
    let allowedSymbols: [String]
}
