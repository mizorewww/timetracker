import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct CoreLLMInboxRequestBudgetTests {
    @Test @MainActor
    func storeCandidateWindowKeepsPinnedAndRecentTasksRelevant() {
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let regularTasks = (0..<60).map { index in
            let task = TaskNode(
                title: String(format: "A%03d", index),
                parentID: nil,
                deviceID: "test"
            )
            task.updatedAt = oldDate.addingTimeInterval(TimeInterval(index))
            return task
        }
        let recentTask = TaskNode(title: "ZZY Recent", parentID: nil, deviceID: "test")
        recentTask.updatedAt = oldDate.addingTimeInterval(10_000)
        let pinnedTask = TaskNode(title: "ZZZ Pinned", parentID: nil, deviceID: "test")
        pinnedTask.updatedAt = oldDate.addingTimeInterval(20_000)

        let store = makeTestStore()
        store.tasks = regularTasks + [recentTask, pinnedTask]
        store.preferences.quickStartTaskIDs = [pinnedTask.id]

        let candidates = store.llmTaskCandidates()
        let candidateIDs = Set(candidates.map(\.id))

        #expect(candidates.count == LLMSuggestionInputPolicy.maximumCandidateCount)
        #expect(candidateIDs.contains(pinnedTask.id))
        #expect(candidateIDs.contains(recentTask.id))
        #expect(
            candidateIDs.intersection(Set(regularTasks.map(\.id))).count ==
                LLMSuggestionInputPolicy.maximumCandidateCount - 2
        )

        let category = TaskCategory(
            title: "Planning",
            deviceID: "test",
            colorHex: "16A34A",
            iconName: "folder"
        )
        store.taskCategories = [category]
        let destinations = store.llmInboxSuggestionCandidates()
        let destinationTaskIDs = Set(destinations.tasks.map(\.id))

        #expect(destinations.tasks.count + destinations.categories.count == 48)
        #expect(destinations.categories.map(\.id) == [category.id])
        #expect(destinationTaskIDs.contains(pinnedTask.id))
        #expect(destinationTaskIDs.contains(recentTask.id))
    }

    @Test @MainActor
    func destinationWindowUsesSpareTaskCapacityForCategories() {
        let store = makeTestStore()
        let task = TaskNode(title: "Only task", parentID: nil, deviceID: "test")
        store.tasks = [task]
        store.taskCategories = (0..<60).map { index in
            TaskCategory(
                title: String(format: "Category %03d", index),
                deviceID: "test",
                colorHex: "16A34A",
                iconName: "folder"
            )
        }

        let destinations = store.llmInboxSuggestionCandidates()

        #expect(destinations.tasks.map(\.id) == [task.id])
        #expect(
            destinations.tasks.count + destinations.categories.count ==
                LLMSuggestionInputPolicy.maximumCandidateCount
        )
        #expect(
            destinations.categories.count ==
                LLMSuggestionInputPolicy.maximumCandidateCount - 1
        )
    }

    @Test
    func inboxPromptUsesCuratedSymbolsWithoutShrinkingThePickerCatalog() throws {
        #expect(SymbolCatalog.symbolNameSet == Set(SymbolCatalog.symbolNames))
        #expect(SymbolCatalog.aiSuggestionSymbolNameSet == Set(SymbolCatalog.aiSuggestionSymbolNames))
        #expect(SymbolCatalog.aiSuggestionSymbolNameSet.contains("book"))
        #expect(SymbolCatalog.aiSuggestionSymbolNameSet.contains("briefcase"))
        #expect(SymbolCatalog.aiSuggestionSymbolNameSet.contains("heart"))
        #expect(SymbolCatalog.aiSuggestionSymbolNameSet.contains("timer"))

        let symbolExcludedFromAI = try #require(
            SymbolCatalog.symbolNames.first {
                !SymbolCatalog.aiSuggestionSymbolNameSet.contains($0)
            }
        )
        let customInstructions = "Prefer the narrowest destination with a concise reason."
        let request = try LLMInboxSuggestionService().suggestionRequest(
            inboxTitle: "Read the architecture notes",
            taskCandidates: [Self.candidate(index: 1)],
            categoryCandidates: [Self.categoryCandidate(index: 1)],
            instructions: customInstructions,
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "test-model"
        )
        let prompt = try Self.decodePrompt(from: request)
        let envelope = try Self.decodeEnvelope(from: request)
        let systemMessage = try #require(envelope.messages.first { $0.role == "system" })

        #expect(prompt.instructions == customInstructions)
        #expect(systemMessage.content.contains("destinationKind"))
        #expect(systemMessage.content.contains("must exactly match an ID"))
        #expect(systemMessage.content.contains("childTask to create a new child task"))
        #expect(prompt.allowedSymbols == SymbolCatalog.aiSuggestionSymbolNames)
        #expect(!prompt.allowedSymbols.contains(symbolExcludedFromAI))
        #expect(prompt.tasks.count == 1)
        #expect(prompt.categories.count == 1)
        #expect(SymbolCatalog.symbolNameSet.contains(symbolExcludedFromAI))
        #expect(prompt.allowedSymbols.count < SymbolCatalog.symbolNames.count)

        let lastPickerSymbol = try #require(SymbolCatalog.symbolNames.last)
        #expect(ChecklistVisualSanitizer.sanitizedIcon(lastPickerSymbol) == lastPickerSymbol)
        #expect(
            ChecklistVisualSanitizer.sanitizedIcon("not.a.real.symbol") ==
                ChecklistVisualSanitizer.defaultIcon
        )
    }

    @Test
    func maximumEditableInboxInstructionsStayWithinRequestBudgets() throws {
        let instructions = String(
            repeating: "\\\"",
            count: AppPreferenceValueSanitizer.maximumLLMPromptInstructionsByteCount / 2
        )
        let tasks = (0..<160).map { index in
            Self.candidate(
                index: index,
                title: String(repeating: "\\\"", count: 180),
                path: String(repeating: "Root/\\\"", count: 100)
            )
        }
        let categories = (0..<80).map { index in
            Self.categoryCandidate(
                index: index,
                title: String(repeating: "\\\"", count: 180)
            )
        }
        let request = try LLMInboxSuggestionService().suggestionRequest(
            inboxTitle: String(repeating: "\\\"", count: 400),
            taskCandidates: tasks,
            categoryCandidates: categories,
            instructions: instructions,
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "test-model"
        )
        let body = try #require(request.httpBody)
        let prompt = try Self.decodePrompt(from: request)
        let envelope = try Self.decodeEnvelope(from: request)
        let userMessage = try #require(envelope.messages.last { $0.role == "user" })

        #expect(prompt.instructions == instructions)
        #expect(!prompt.tasks.isEmpty)
        #expect(!prompt.categories.isEmpty)
        #expect(body.count <= LLMSuggestionInputPolicy.maximumRequestBodyByteCount)
        #expect(userMessage.content.utf8.count <= LLMSuggestionInputPolicy.maximumPromptByteCount)
    }

    @Test
    func candidateBudgetIsDeterministicAndUTF8Safe() throws {
        var candidates = (0..<120).map { index in
            Self.candidate(
                index: index,
                title: "  \(String(repeating: "任务🧭", count: 120)) \(index)  ",
                path: "  \(String(repeating: "Project/工作🚀/", count: 100))\(index)  "
            )
        }
        candidates.append(candidates[17])

        let forward = LLMSuggestionInputPolicy.boundedCandidates(candidates)
        let reverse = LLMSuggestionInputPolicy.boundedCandidates(candidates.reversed())
        let encoded = try JSONEncoder().encode(forward)

        #expect(forward == reverse)
        #expect(!forward.isEmpty)
        #expect(forward.count <= LLMSuggestionInputPolicy.maximumCandidateCount)
        #expect(encoded.count <= LLMSuggestionInputPolicy.maximumCandidateJSONByteCount)
        #expect(Set(forward.map(\.id)).count == forward.count)
        #expect(
            forward.allSatisfy {
                !$0.title.isEmpty &&
                    $0.title.utf8.count <= LLMSuggestionInputPolicy.maximumCandidateTitleByteCount &&
                    $0.path.utf8.count <= LLMSuggestionInputPolicy.maximumCandidatePathByteCount
            }
        )
        #expect(forward.allSatisfy { String(data: Data($0.title.utf8), encoding: .utf8) == $0.title })
        #expect(forward.allSatisfy { String(data: Data($0.path.utf8), encoding: .utf8) == $0.path })
    }

    @Test
    func taskAndCategoryCandidatesShareBudgetsWithoutCrowdingOutCategories() throws {
        let tasks = (0..<120).map { index in
            Self.candidate(
                index: index,
                title: "  \(String(repeating: "任务🧭", count: 100)) \(index)  ",
                path: "  \(String(repeating: "Project/工作🚀/", count: 80))\(index)  "
            )
        }
        let categories = (0..<20).map { index in
            Self.categoryCandidate(
                index: index,
                title: "  \(String(repeating: "分类🗂️", count: 100)) \(index)  "
            )
        }

        let forward = LLMSuggestionInputPolicy.boundedDestinationCandidates(
            tasks: tasks,
            categories: categories
        )
        let reverse = LLMSuggestionInputPolicy.boundedDestinationCandidates(
            tasks: tasks.reversed(),
            categories: categories.reversed()
        )
        let encoded = try JSONEncoder().encode(forward)

        #expect(forward == reverse)
        #expect(!forward.tasks.isEmpty)
        #expect(!forward.categories.isEmpty)
        #expect(
            forward.tasks.count + forward.categories.count <=
                LLMSuggestionInputPolicy.maximumCandidateCount
        )
        #expect(encoded.count <= LLMSuggestionInputPolicy.maximumCandidateJSONByteCount)
        #expect(Set(forward.tasks.map(\.id)).count == forward.tasks.count)
        #expect(Set(forward.categories.map(\.id)).count == forward.categories.count)
        #expect(
            forward.categories.allSatisfy {
                !$0.title.isEmpty &&
                    $0.title.utf8.count <=
                    LLMSuggestionInputPolicy.maximumCandidateTitleByteCount
            }
        )
    }

    @Test
    func finalRequestStaysWithinPromptAndBodyBudgets() throws {
        let candidates = (0..<160).map { index in
            Self.candidate(
                index: index,
                title: String(repeating: "\"复杂任务🧠\\", count: 100),
                path: String(repeating: "Root/项目/\"研究🚀\\/", count: 80)
            )
        }
        let request = try LLMInboxSuggestionService().suggestionRequest(
            inboxTitle: String(repeating: "  \"整理资料🗂️\\  ", count: 300),
            taskCandidates: candidates,
            categoryCandidates: (0..<80).map {
                Self.categoryCandidate(
                    index: $0,
                    title: String(repeating: "\"分类🧭\\", count: 100)
                )
            },
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: String(repeating: "模型🧪", count: 300)
        )
        let body = try #require(request.httpBody)
        let envelope = try JSONDecoder().decode(RequestEnvelope.self, from: body)
        let userMessage = try #require(envelope.messages.last { $0.role == "user" })
        let prompt = try JSONDecoder().decode(PromptEnvelope.self, from: Data(userMessage.content.utf8))

        #expect(body.count <= LLMSuggestionInputPolicy.maximumRequestBodyByteCount)
        #expect(userMessage.content.utf8.count <= LLMSuggestionInputPolicy.maximumPromptByteCount)
        #expect(envelope.model.utf8.count <= LLMSuggestionInputPolicy.maximumModelIDByteCount)
        #expect(prompt.inboxTitle.utf8.count <= LLMSuggestionInputPolicy.maximumInboxTitleByteCount)
        #expect(
            prompt.tasks.count + prompt.categories.count <=
                LLMSuggestionInputPolicy.maximumCandidateCount
        )
        #expect(prompt.allowedSymbols == SymbolCatalog.aiSuggestionSymbolNames)
        #expect(!prompt.tasks.isEmpty)
        #expect(!prompt.categories.isEmpty)
        #expect(
            try JSONEncoder().encode(
                LLMInboxSuggestionCandidates(
                    tasks: prompt.tasks,
                    categories: prompt.categories
                )
            ).count <= LLMSuggestionInputPolicy.maximumCandidateJSONByteCount
        )
    }

    @Test
    func normalSuggestionResultSurvivesInputBudgeting() async throws {
        let candidate = Self.candidate(index: 42, title: "Research", path: "Work / Research")
        let service = LLMInboxSuggestionService { request in
            let prompt = try Self.decodePrompt(from: request)
            let transmittedCandidate = try #require(prompt.tasks.first)
            let payload = InboxSuggestionPayload(
                destinationKind: InboxSuggestionDestinationKind.checklist.rawValue,
                destinationID: transmittedCandidate.id.uuidString,
                reason: "  Same project  ",
                iconName: "book",
                colorHex: "1677FF"
            )
            let content = try #require(String(data: JSONEncoder().encode(payload), encoding: .utf8))
            let responseData = try JSONSerialization.data(
                withJSONObject: ["choices": [["message": ["content": content]]]]
            )
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (responseData, response)
        }

        let result = try await service.suggest(
            inboxTitle: "Read the paper",
            taskCandidates: [candidate],
            categoryCandidates: [],
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "test-model"
        )

        #expect(result.destination == .checklist(taskID: candidate.id))
        #expect(result.reason == "Same project")
        #expect(result.iconName == "book")
        #expect(result.colorHex == "1677FF")
        #expect(result.modelID == "test-model")
    }

    @Test
    func responseTextAndVisualFieldsAreBounded() throws {
        let candidate = Self.candidate(index: 7)
        let payload = InboxSuggestionPayload(
            destinationKind: InboxSuggestionDestinationKind.childTask.rawValue,
            destinationID: candidate.id.uuidString,
            reason: String(repeating: "理由🧩", count: 400),
            iconName: String(repeating: "trash", count: 100),
            colorHex: String(repeating: "#007AFF", count: 100)
        )
        let result = try LLMInboxSuggestionService.sanitize(
            payload: payload,
            taskCandidates: [candidate],
            categoryCandidates: [],
            modelID: String(repeating: "模型🧪", count: 300)
        )

        #expect(result.destination == .childTask(parentTaskID: candidate.id))
        #expect(result.reason.utf8.count <= LLMSuggestionInputPolicy.maximumReasonByteCount)
        #expect(String(data: Data(result.reason.utf8), encoding: .utf8) == result.reason)
        #expect(result.iconName == ChecklistVisualSanitizer.defaultIcon)
        #expect(result.colorHex == candidate.colorHex)
        #expect(result.modelID.utf8.count <= LLMSuggestionInputPolicy.maximumModelIDByteCount)
    }

    @Test @MainActor
    func categoryOnlySuggestionCanGenerateAndNoDestinationsKeepTheOriginalError() async throws {
        let category = Self.categoryCandidate(index: 9, title: "Health")
        let service = LLMInboxSuggestionService { request in
            let prompt = try Self.decodePrompt(from: request)
            #expect(prompt.tasks.isEmpty)
            let transmittedCategory = try #require(prompt.categories.first)
            let payload = InboxSuggestionPayload(
                destinationKind: InboxSuggestionDestinationKind.category.rawValue,
                destinationID: transmittedCategory.id.uuidString,
                reason: "Daily habit",
                iconName: "heart",
                colorHex: transmittedCategory.colorHex
            )
            let content = try #require(
                String(data: JSONEncoder().encode(payload), encoding: .utf8)
            )
            let responseData = try JSONSerialization.data(
                withJSONObject: ["choices": [["message": ["content": content]]]]
            )
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (responseData, response)
        }

        let result = try await service.suggest(
            inboxTitle: "Do 50 push-ups",
            taskCandidates: [],
            categoryCandidates: [category],
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "test-model"
        )
        #expect(result.destination == .category(categoryID: category.id))

        #expect(throws: LLMInboxSuggestionServiceError.noTaskCandidates) {
            try LLMInboxSuggestionService().suggestionRequest(
                inboxTitle: "Nowhere to route",
                taskCandidates: [],
                categoryCandidates: [],
                endpoint: "https://example.com/v1",
                apiKey: "secret",
                modelID: "test-model"
            )
        }
    }

    @Test
    func responseDestinationMustMatchAnActuallyTransmittedCandidateTable() {
        let task = Self.candidate(index: 12)
        let category = Self.categoryCandidate(index: 12)

        func payload(kind: String, id: String) -> InboxSuggestionPayload {
            InboxSuggestionPayload(
                destinationKind: kind,
                destinationID: id,
                reason: "Match",
                iconName: "book",
                colorHex: "1677FF"
            )
        }

        let rejectedPayloads = [
            payload(kind: "futureDestination", id: task.id.uuidString),
            payload(kind: "checklist", id: "not-a-uuid"),
            payload(kind: "category", id: task.id.uuidString),
            payload(kind: "childTask", id: category.id.uuidString),
            payload(kind: "checklist", id: UUID().uuidString),
            payload(kind: "category", id: UUID().uuidString),
        ]
        for rejectedPayload in rejectedPayloads {
            #expect(throws: LLMInboxSuggestionServiceError.noValidTask) {
                try LLMInboxSuggestionService.sanitize(
                    payload: rejectedPayload,
                    taskCandidates: [task],
                    categoryCandidates: [category],
                    modelID: "test-model"
                )
            }
        }
    }

    @Test
    func responseDestinationFieldTypeMismatchIsRejected() async throws {
        let task = Self.candidate(index: 13)
        let service = LLMInboxSuggestionService { request in
            let content = """
            {"destinationKind":"checklist","destinationID":42,"reason":"Match","iconName":"book","colorHex":"1677FF"}
            """
            let responseData = try JSONSerialization.data(
                withJSONObject: ["choices": [["message": ["content": content]]]]
            )
            let response = try #require(
                HTTPURLResponse(
                    url: request.url ?? URL(string: "https://example.com")!,
                    statusCode: 200,
                    httpVersion: nil,
                    headerFields: nil
                )
            )
            return (responseData, response)
        }

        do {
            _ = try await service.suggest(
                inboxTitle: "Read the paper",
                taskCandidates: [task],
                categoryCandidates: [],
                endpoint: "https://example.com/v1",
                apiKey: "secret",
                modelID: "test-model"
            )
            Issue.record("Expected destinationID type mismatch to be rejected")
        } catch let error as LLMInboxSuggestionServiceError {
            #expect(error == .invalidResponse)
        }
    }

    private static func candidate(
        index: Int,
        title: String = "Task",
        path: String = "Project / Task"
    ) -> LLMTaskCandidate {
        LLMTaskCandidate(
            id: UUID(uuidString: String(format: "00000000-0000-0000-0000-%012d", index))!,
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
            id: UUID(uuidString: String(format: "10000000-0000-0000-0000-%012d", index))!,
            title: "\(title) \(index)",
            iconName: "folder",
            colorHex: "16A34A"
        )
    }

    private static func decodePrompt(from request: URLRequest) throws -> PromptEnvelope {
        let envelope = try decodeEnvelope(from: request)
        let userMessage = try #require(envelope.messages.last { $0.role == "user" })
        return try JSONDecoder().decode(PromptEnvelope.self, from: Data(userMessage.content.utf8))
    }

    private static func decodeEnvelope(from request: URLRequest) throws -> RequestEnvelope {
        let body = try #require(request.httpBody)
        return try JSONDecoder().decode(RequestEnvelope.self, from: body)
    }
}

private struct RequestEnvelope: Decodable {
    let model: String
    let messages: [Message]

    struct Message: Decodable {
        let role: String
        let content: String
    }
}

private struct PromptEnvelope: Codable {
    let instructions: String
    let inboxTitle: String
    let allowedSymbols: [String]
    let allowedColors: [String]
    let tasks: [LLMTaskCandidate]
    let categories: [LLMCategoryCandidate]
}
