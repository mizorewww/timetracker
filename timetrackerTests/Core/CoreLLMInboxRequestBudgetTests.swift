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

        let store = TimeTrackerStore()
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
        let request = try LLMInboxSuggestionService().suggestionRequest(
            inboxTitle: "Read the architecture notes",
            candidates: [Self.candidate(index: 1)],
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "test-model"
        )
        let prompt = try Self.decodePrompt(from: request)

        #expect(prompt.allowedSymbols == SymbolCatalog.aiSuggestionSymbolNames)
        #expect(!prompt.allowedSymbols.contains(symbolExcludedFromAI))
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
            candidates: candidates,
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
        #expect(prompt.tasks.count <= LLMSuggestionInputPolicy.maximumCandidateCount)
        #expect(prompt.allowedSymbols == SymbolCatalog.aiSuggestionSymbolNames)
        #expect(!prompt.tasks.isEmpty)
    }

    @Test
    func normalSuggestionResultSurvivesInputBudgeting() async throws {
        let candidate = Self.candidate(index: 42, title: "Research", path: "Work / Research")
        let service = LLMInboxSuggestionService { request in
            let prompt = try Self.decodePrompt(from: request)
            let transmittedCandidate = try #require(prompt.tasks.first)
            let payload = InboxSuggestionPayload(
                taskID: transmittedCandidate.id.uuidString,
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
            candidates: [candidate],
            endpoint: "https://example.com/v1",
            apiKey: "secret",
            modelID: "test-model"
        )

        #expect(result.taskID == candidate.id)
        #expect(result.reason == "Same project")
        #expect(result.iconName == "book")
        #expect(result.colorHex == "1677FF")
        #expect(result.modelID == "test-model")
    }

    @Test
    func responseTextAndVisualFieldsAreBounded() throws {
        let candidate = Self.candidate(index: 7)
        let payload = InboxSuggestionPayload(
            taskID: candidate.id.uuidString,
            reason: String(repeating: "理由🧩", count: 400),
            iconName: String(repeating: "trash", count: 100),
            colorHex: String(repeating: "#007AFF", count: 100)
        )
        let result = try LLMInboxSuggestionService.sanitize(
            payload: payload,
            candidates: [candidate],
            modelID: String(repeating: "模型🧪", count: 300)
        )

        #expect(result.reason.utf8.count <= LLMSuggestionInputPolicy.maximumReasonByteCount)
        #expect(String(data: Data(result.reason.utf8), encoding: .utf8) == result.reason)
        #expect(result.iconName == ChecklistVisualSanitizer.defaultIcon)
        #expect(result.colorHex == candidate.colorHex)
        #expect(result.modelID.utf8.count <= LLMSuggestionInputPolicy.maximumModelIDByteCount)
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

    private static func decodePrompt(from request: URLRequest) throws -> PromptEnvelope {
        let body = try #require(request.httpBody)
        let envelope = try JSONDecoder().decode(RequestEnvelope.self, from: body)
        let userMessage = try #require(envelope.messages.last { $0.role == "user" })
        return try JSONDecoder().decode(PromptEnvelope.self, from: Data(userMessage.content.utf8))
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

private struct PromptEnvelope: Decodable {
    let inboxTitle: String
    let allowedSymbols: [String]
    let tasks: [LLMTaskCandidate]
}
