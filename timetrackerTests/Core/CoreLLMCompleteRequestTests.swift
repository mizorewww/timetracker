import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLLMCompleteRequestTests {
    @Test @MainActor
    func storeExposesEveryEligibleTaskAndCategoryToInboxRouting() {
        let store = makeTestStore()
        let tasks = (0 ..< 80).map { index in
            TaskNode(
                title: String(format: "Task %03d", index),
                parentID: nil,
                deviceID: "test"
            )
        }
        let categories = (0 ..< 60).map { index in
            TaskCategory(
                title: String(format: "Category %03d", index),
                deviceID: "test",
                colorHex: "16A34A",
                iconName: "folder"
            )
        }
        store.tasks = tasks
        store.taskCategories = categories

        let destinations = store.llmInboxSuggestionCandidates()

        #expect(Set(destinations.tasks.map(\.id)) == Set(tasks.map(\.id)))
        #expect(
            Set(destinations.categories.map(\.id)) ==
                Set(categories.map(\.id))
        )
    }

    @Test
    func inboxRequestSerializesEveryCandidateAndCompleteUnicodeField() throws {
        let inboxTitle = String(
            repeating: "  整理完整研究资料🗂️  ",
            count: 80
        )
        var tasks = (0 ..< 120).map { index in
            Self.candidate(
                index: index,
                title: String(repeating: "复杂任务🧠", count: 80),
                path: String(repeating: "Root/项目/研究🚀/", count: 60)
            )
        }
        tasks.append(tasks[17])
        let categories = (0 ..< 40).map { index in
            Self.categoryCandidate(
                index: index,
                title: String(repeating: "完整分类🧭", count: 80)
            )
        }

        let request = try LLMInboxSuggestionService().suggestionRequest(
            inboxTitle: inboxTitle,
            taskCandidates: tasks,
            categoryCandidates: categories,
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "deepseek-v4-flash"
        )
        let body = try #require(request.httpBody)
        let prompt = try Self.decodeInboxPrompt(from: request)

        #expect(prompt.inboxTitle == inboxTitle.trimmingCharacters(
            in: .whitespacesAndNewlines
        ))
        #expect(prompt.tasks.count == 120)
        #expect(prompt.categories.count == 40)
        #expect(Set(prompt.tasks.map(\.id)).count == 120)
        #expect(
            prompt.tasks.first { $0.id == tasks[119].id }?.title ==
                tasks[119].title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
        #expect(
            prompt.tasks.first { $0.id == tasks[119].id }?.path ==
                tasks[119].path.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
        )
        #expect(prompt.allowedSymbols == SymbolCatalog.symbolNames)
        #expect(prompt.allowedSymbols.count > 1000)
        #expect(body.count > 64 * 1024)
    }

    @Test
    func checklistRequestSerializesCompleteContextAndFullSymbolCatalog() throws {
        let checklistTitle = String(
            repeating: "检查完整细节🧩",
            count: 500
        )
        let taskTitle = String(
            repeating: "产品设计🎨",
            count: 500
        )
        let taskPath = String(
            repeating: "Root/项目/完整设计🚀/",
            count: 500
        )
        let request = try LLMChecklistVisualSuggestionService()
            .suggestionRequest(
                checklistTitle: checklistTitle,
                taskTitle: taskTitle,
                taskPath: taskPath,
                endpoint: "https://example.com/v1",
                apiKey: "secret",
                modelID: "deepseek-v4-flash"
            )
        let body = try #require(request.httpBody)
        let prompt = try Self.decodeChecklistPrompt(from: request)

        #expect(prompt.checklistTitle == checklistTitle)
        #expect(prompt.taskTitle == taskTitle)
        #expect(prompt.taskPath == taskPath)
        #expect(prompt.allowedSymbols == SymbolCatalog.symbolNames)
        #expect(prompt.allowedSymbols.last == SymbolCatalog.symbolNames.last)
        #expect(body.count > 64 * 1024)
    }

    @Test
    func modelIdentifierIsValidatedWholeInsteadOfSilentlyTruncated() {
        let oversizedModelID = String(
            repeating: "m",
            count: AppPreferenceValueSanitizer.maximumLLMModelIDByteCount + 1
        )

        #expect(throws: LLMInboxSuggestionServiceError.missingModel) {
            try LLMInboxSuggestionService().suggestionRequest(
                inboxTitle: "Read the paper",
                taskCandidates: [Self.candidate(index: 1)],
                categoryCandidates: [],
                endpoint: "https://example.com/v1",
                apiKey: "secret",
                modelID: oversizedModelID
            )
        }
    }

    @Test
    func responseValidationAcceptsEveryAdvertisedSymbol() {
        let lastSymbol = SymbolCatalog.symbolNames.last
        let result = LLMChecklistVisualSuggestionService.sanitize(
            payload: ChecklistVisualSuggestionPayload(
                iconName: lastSymbol ?? "",
                colorHex: "1677FF",
                reason: "Matches the complete catalog"
            ),
            modelID: "deepseek-v4-flash"
        )

        #expect(SymbolCatalog.symbolNames.count > 1000)
        #expect(result.iconName == lastSymbol)
    }

    @Test
    func responseDestinationStillRequiresAnActuallyTransmittedCandidate() {
        let task = Self.candidate(index: 12)
        let category = Self.categoryCandidate(index: 12)
        let payload = InboxSuggestionPayload(
            destinationKind: "checklist",
            destinationID: UUID().uuidString,
            reason: "Unknown destination",
            iconName: "book",
            colorHex: "1677FF"
        )

        #expect(throws: LLMInboxSuggestionServiceError.noValidTask) {
            try LLMInboxSuggestionService.sanitize(
                payload: payload,
                taskCandidates: [task],
                categoryCandidates: [category],
                modelID: "deepseek-v4-flash"
            )
        }
    }

    @Test
    func credentialHeaderKeepsItsExplicitSafetyBoundary() {
        #expect(throws: LLMInboxSuggestionServiceError.requestTooLarge) {
            try LLMChecklistVisualSuggestionService().suggestionRequest(
                checklistTitle: "Polish spacing",
                taskTitle: "Design",
                taskPath: "Work / Design",
                endpoint: "https://example.com/v1",
                apiKey: String(
                    repeating: "k",
                    count:
                    LLMSuggestionInputPolicy.maximumAPIKeyByteCount + 1
                ),
                modelID: "deepseek-v4-flash"
            )
        }
    }

    private static func candidate(
        index: Int,
        title: String = "Task",
        path: String = "Project / Task"
    ) -> LLMTaskCandidate {
        LLMTaskCandidate(
            id: UUID(
                uuidString: String(
                    format: "00000000-0000-0000-0000-%012d",
                    index
                )
            )!,
            title: "\(title) \(index)",
            path: "\(path) \(index)",
            iconName: "book",
            colorHex: "1677FF"
        )
    }

    private static func categoryCandidate(
        index: Int,
        title: String = "Category"
    ) -> LLMCategoryCandidate {
        LLMCategoryCandidate(
            id: UUID(
                uuidString: String(
                    format: "10000000-0000-0000-0000-%012d",
                    index
                )
            )!,
            title: "\(title) \(index)",
            iconName: "folder",
            colorHex: "16A34A"
        )
    }

    private static func decodeInboxPrompt(
        from request: URLRequest
    ) throws -> InboxPromptEnvelope {
        let envelope = try decodeRequestEnvelope(from: request)
        let userMessage = try #require(
            envelope.messages.last { $0.role == "user" }
        )
        return try JSONDecoder().decode(
            InboxPromptEnvelope.self,
            from: Data(userMessage.content.utf8)
        )
    }

    private static func decodeChecklistPrompt(
        from request: URLRequest
    ) throws -> ChecklistPromptEnvelope {
        let envelope = try decodeRequestEnvelope(from: request)
        let userMessage = try #require(
            envelope.messages.last { $0.role == "user" }
        )
        return try JSONDecoder().decode(
            ChecklistPromptEnvelope.self,
            from: Data(userMessage.content.utf8)
        )
    }

    private static func decodeRequestEnvelope(
        from request: URLRequest
    ) throws -> RequestEnvelope {
        let body = try #require(request.httpBody)
        return try JSONDecoder().decode(RequestEnvelope.self, from: body)
    }
}

private struct RequestEnvelope: Decodable {
    let messages: [Message]

    struct Message: Decodable {
        let role: String
        let content: String
    }
}

private struct InboxPromptEnvelope: Decodable {
    let inboxTitle: String
    let allowedSymbols: [String]
    let tasks: [LLMTaskCandidate]
    let categories: [LLMCategoryCandidate]
}

private struct ChecklistPromptEnvelope: Decodable {
    let checklistTitle: String
    let taskTitle: String
    let taskPath: String
    let allowedSymbols: [String]
}
