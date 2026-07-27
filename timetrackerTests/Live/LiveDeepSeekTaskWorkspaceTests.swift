import Foundation
import SwiftData
@testable import timetracker
import XCTest

@MainActor
final class LiveDeepSeekTaskWorkspaceTests: XCTestCase {
    private static let prompt28 =
        "帮我生成 category阅读，下放一个任务：人工智能：现代方法，生成checklist 1-28"
    private static let prompt150 =
        "帮我生成 category阅读，下放一个任务：人工智能：现代方法，生成checklist 1-150"
    private static let semanticHierarchyPrompt = """
    Only refine the existing task "Phoenix Release". Do not change or add \
    any other root task or category.
    Under it, create two child Tasks that must be timed independently, with \
    the exact titles "Run Data Migration [TRACK-A]" and \
    "Write Release Notes [TRACK-B]".
    Inside "Run Data Migration [TRACK-A]", create three untimed steps that \
    are completed only by checking them off, with the exact Checklist titles \
    "Back Up Database [STEP-A1]", "Run Migration [STEP-A2]", and \
    "Verify Rollback [STEP-A3]".
    Inside "Write Release Notes [TRACK-B]", create two equivalent untimed \
    Checklist steps with the exact titles "Summarize Changes [STEP-B1]" and \
    "Proofread Copy [STEP-B2]".
    Never create a TRACK item as a Checklist item, and never create a STEP \
    item as a Task.
    """

    func testPrompt28UsesTheProductionDeepSeekService() async throws {
        let configuration = try liveConfiguration(for: "prompt28")
        let workspace = AITaskWorkspaceSnapshot(
            categories: [],
            tasks: [],
            checklistItems: []
        )

        let plan = try await generate(
            prompt: Self.prompt28,
            workspace: workspace,
            configuration: configuration
        )

        _ = try verifyGeneratedWorkspace(
            plan.resultingSnapshot,
            expectedChecklistCount: 28
        )
        XCTAssertGreaterThanOrEqual(plan.toolRoundCount, 1)
        XCTAssertGreaterThanOrEqual(plan.toolCallCount, 31)
        XCTAssertFalse(plan.reasoningContent?.isEmpty ?? true)
        XCTAssertNotNil(plan.rawResponseContent)
    }

    func testPrompt150AppliesToAnIsolatedSwiftDataStore() async throws {
        let configuration = try liveConfiguration(for: "prompt150")
        let context = try makeTestContext()
        let coordinator = StoreScopedAITaskAtomicMutationCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "live-deepseek-harness"
        )
        let baseline = try coordinator.captureBaseline()

        let plan = try await generate(
            prompt: Self.prompt150,
            workspace: baseline.snapshot,
            configuration: configuration
        )
        let generatedTaskID = try verifyGeneratedWorkspace(
            plan.resultingSnapshot,
            expectedChecklistCount: 150
        )
        XCTAssertGreaterThanOrEqual(plan.toolCallCount, 153)
        XCTAssertFalse(plan.reasoningContent?.isEmpty ?? true)
        XCTAssertNotNil(plan.rawResponseContent)

        let outcome = try coordinator.apply(
            AITaskAtomicMutationPlan(
                baseline: baseline,
                operations: plan.operations
            )
        )
        XCTAssertTrue(outcome.didMutateTasks)
        XCTAssertTrue(outcome.didMutateChecklists)

        let persisted = ModelContext(context.container)
        let categories = try persisted.fetch(
            FetchDescriptor<TaskCategory>()
        ).visibleDeduplicatedByID()
        let tasks = try persisted.fetch(
            FetchDescriptor<TaskNode>()
        ).visibleDeduplicatedByID()
        let checklistItems = try persisted.fetch(
            FetchDescriptor<ChecklistItem>()
        ).visibleDeduplicatedByID()

        XCTAssertEqual(categories.map(\.title), ["阅读"])
        XCTAssertEqual(tasks.map(\.title), ["人工智能：现代方法"])
        XCTAssertEqual(tasks.first?.id, generatedTaskID)
        XCTAssertEqual(checklistItems.count, 150)
        XCTAssertEqual(
            Set(checklistItems.map(\.taskID)),
            [generatedTaskID]
        )
    }

    func testMixedTaskHierarchySemanticsUseTheProductionDeepSeekService()
        async throws
    {
        let configuration = try liveConfiguration(for: "semantics")
        let context = try makeTestContext()
        let repository = SwiftDataTaskRepository(
            context: context,
            deviceID: "live-deepseek-harness"
        )
        let root = try repository.createTask(
            title: "Phoenix Release",
            parentID: nil,
            colorHex: "1677FF",
            iconName: "shippingbox"
        )
        let coordinator = StoreScopedAITaskAtomicMutationCoordinator(
            container: context.container,
            writeAuthorization: .isolatedTestHarness,
            deviceID: "live-deepseek-harness"
        )
        let baseline = try coordinator.captureBaseline()

        let plan = try await generate(
            prompt: Self.semanticHierarchyPrompt,
            workspace: baseline.snapshot,
            configuration: configuration
        )

        let resultingTasks = plan.resultingSnapshot.tasks
        let rootAfter = try XCTUnwrap(
            resultingTasks.first { $0.id == root.id }
        )
        XCTAssertEqual(rootAfter.title, root.title)
        XCTAssertNil(rootAfter.parentID)
        XCTAssertEqual(resultingTasks.count, 3)
        XCTAssertEqual(plan.resultingSnapshot.categories.count, 0)

        let trackedTitles = [
            "Run Data Migration [TRACK-A]",
            "Write Release Notes [TRACK-B]",
        ]
        let trackedTasks = try trackedTitles.map { title in
            try XCTUnwrap(
                resultingTasks.first { $0.title == title },
                "Missing independently timed child Task: \(title)"
            )
        }
        XCTAssertTrue(trackedTasks.allSatisfy { $0.parentID == root.id })
        XCTAssertTrue(trackedTasks.allSatisfy { $0.categoryID == nil })

        let expectedChecklistTitlesByTask = [
            trackedTasks[0].id: Set([
                "Back Up Database [STEP-A1]",
                "Run Migration [STEP-A2]",
                "Verify Rollback [STEP-A3]",
            ]),
            trackedTasks[1].id: Set([
                "Summarize Changes [STEP-B1]",
                "Proofread Copy [STEP-B2]",
            ]),
        ]
        XCTAssertEqual(plan.resultingSnapshot.checklistItems.count, 5)
        for (taskID, expectedTitles) in expectedChecklistTitlesByTask {
            XCTAssertEqual(
                Set(
                    plan.resultingSnapshot.checklistItems
                        .filter { $0.taskID == taskID }
                        .map(\.title)
                ),
                expectedTitles
            )
        }
        XCTAssertTrue(
            plan.resultingSnapshot.checklistItems.allSatisfy {
                $0.taskID != root.id
            }
        )
        XCTAssertFalse(
            resultingTasks.contains {
                $0.title.contains("[STEP-")
            }
        )
        XCTAssertFalse(
            plan.resultingSnapshot.checklistItems.contains {
                $0.title.contains("[TRACK-")
            }
        )
        XCTAssertGreaterThanOrEqual(plan.toolCallCount, 8)
        XCTAssertFalse(plan.reasoningContent?.isEmpty ?? true)
        XCTAssertNotNil(plan.rawResponseContent)

        let outcome = try coordinator.apply(
            AITaskAtomicMutationPlan(
                baseline: baseline,
                operations: plan.operations
            )
        )
        XCTAssertTrue(outcome.didMutateTasks)
        XCTAssertTrue(outcome.didMutateChecklists)

        let persisted = ModelContext(context.container)
        let persistedTasks = try persisted.fetch(
            FetchDescriptor<TaskNode>()
        ).visibleDeduplicatedByID()
        let persistedChecklistItems = try persisted.fetch(
            FetchDescriptor<ChecklistItem>()
        ).visibleDeduplicatedByID()
        XCTAssertEqual(persistedTasks.count, 3)
        XCTAssertEqual(persistedChecklistItems.count, 5)
        for (taskID, expectedTitles) in expectedChecklistTitlesByTask {
            XCTAssertEqual(
                Set(
                    persistedChecklistItems
                        .filter { $0.taskID == taskID }
                        .map(\.title)
                ),
                expectedTitles
            )
        }
    }

    func testInboxRoutingPromptUsesTheProductionDeepSeekService() async throws {
        let configuration = try liveConfiguration(for: "prompts")
        let readingTaskID = UUID(
            uuidString: "A1000000-0000-0000-0000-000000000001"
        )!

        let result = try await LLMInboxSuggestionService().suggest(
            inboxTitle: "Read chapter 3 of Artificial Intelligence: A Modern Approach",
            taskCandidates: [
                LLMTaskCandidate(
                    id: readingTaskID,
                    title: "Artificial Intelligence: A Modern Approach",
                    path: "Reading / Artificial Intelligence: A Modern Approach",
                    iconName: "book",
                    colorHex: "1677FF"
                ),
            ],
            categoryCandidates: [],
            instructions: LLMPromptKind.inboxRouting.defaultInstructions,
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            modelID: configuration.modelID,
            reasoningEffort: .max
        )

        XCTAssertEqual(
            result.destination,
            .checklist(taskID: readingTaskID)
        )
        XCTAssertFalse(result.reason.isEmpty)
        XCTAssertTrue(
            SymbolCatalog.symbolNameSet.contains(result.iconName)
        )
        XCTAssertTrue(TaskColorPalette.hexValues.contains(result.colorHex))
        XCTAssertEqual(result.modelID, configuration.modelID)
    }

    func testChecklistVisualPromptUsesTheProductionDeepSeekService() async throws {
        let configuration = try liveConfiguration(for: "prompts")

        let result = try await LLMChecklistVisualSuggestionService().suggest(
            checklistTitle: "Read chapter 3: Solving Problems by Searching",
            taskTitle: "Artificial Intelligence: A Modern Approach",
            taskPath: "Reading / Artificial Intelligence: A Modern Approach",
            instructions: LLMPromptKind.checklistVisual.defaultInstructions,
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            modelID: configuration.modelID,
            reasoningEffort: .max
        )

        XCTAssertTrue(
            SymbolCatalog.symbolNameSet.contains(result.iconName)
        )
        XCTAssertTrue(TaskColorPalette.hexValues.contains(result.colorHex))
        XCTAssertFalse(result.reason.isEmpty)
        XCTAssertEqual(result.modelID, configuration.modelID)
    }
}

private extension LiveDeepSeekTaskWorkspaceTests {
    struct LiveConfiguration {
        let endpoint: String
        let apiKey: String
        let modelID: String
    }

    enum LiveConfigurationError: Error {
        case missingAPIKey
    }

    func liveConfiguration(
        for requiredScenario: String
    ) throws -> LiveConfiguration {
        let directory = try projectRootURL()
            .appending(path: "build/LiveLLMHarness")
        let runMarker = directory.appending(path: "run")
        guard FileManager.default.fileExists(atPath: runMarker.path) else {
            throw XCTSkip(
                "Live DeepSeek verification is opt-in; use make test-llm-live."
            )
        }

        let selectedScenario = try String(
            contentsOf: directory.appending(path: "scenario"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard selectedScenario == "all" ||
            selectedScenario == requiredScenario
        else {
            throw XCTSkip(
                "The selected live scenario is \(selectedScenario)."
            )
        }

        let apiKey = try String(
            contentsOf: directory.appending(path: "api-key"),
            encoding: .utf8
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        guard apiKey.isEmpty == false else {
            XCTFail("The live API key file is empty.")
            throw LiveConfigurationError.missingAPIKey
        }

        return try LiveConfiguration(
            endpoint: String(
                contentsOf: directory.appending(path: "endpoint"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines),
            apiKey: apiKey,
            modelID: String(
                contentsOf: directory.appending(path: "model"),
                encoding: .utf8
            ).trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    func generate(
        prompt: String,
        workspace: AITaskWorkspaceSnapshot,
        configuration: LiveConfiguration
    ) async throws -> LLMTaskWorkspacePlan {
        var latestToolSummary = "No provider tool response was decoded."
        let service = LLMTaskWorkspacePlanningService { request in
            let response = try await LLMSecureHTTPTransport.data(for: request)
            latestToolSummary = Self.redactedToolSummary(response.0)
            return response
        }
        do {
            return try await service.generate(
                request: prompt,
                instructions: LLMTaskPlanPrompt.defaultInstructions,
                workspace: workspace,
                endpoint: configuration.endpoint,
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                reasoningEffort: .max
            )
        } catch {
            XCTFail(
                "Live provider failed after: \(latestToolSummary)"
            )
            throw error
        }
    }

    static func redactedToolSummary(_ data: Data) -> String {
        guard
            let object = try? JSONSerialization.jsonObject(with: data),
            let envelope = object as? [String: Any],
            let choices = envelope["choices"] as? [[String: Any]],
            let message = choices.first?["message"] as? [String: Any],
            let calls = message["tool_calls"] as? [[String: Any]]
        else {
            return "Provider response had no decodable tool calls."
        }
        return calls.map { call in
            guard
                let function = call["function"] as? [String: Any],
                let name = function["name"] as? String
            else {
                return "unnamed tool call"
            }
            guard
                name == AITaskWorkspaceToolName.createTask.rawValue,
                let arguments = function["arguments"] as? String,
                let argumentData = arguments.data(using: .utf8),
                let value = try? JSONSerialization.jsonObject(
                    with: argumentData
                ),
                let dictionary = value as? [String: Any]
            else {
                return name
            }
            let keys = Set(dictionary.keys)
            let missing = LLMTaskWorkspacePlanningService.taskCreateKeys
                .subtracting(keys)
                .sorted()
            let extra = keys.subtracting(
                LLMTaskWorkspacePlanningService.taskCreateKeys
            ).sorted()
            let iconIsAllowed = (dictionary["iconName"] as? String)
                .map(SymbolCatalog.symbolNameSet.contains) ?? false
            let colorIsAllowed = (dictionary["colorHex"] as? String)
                .map(TaskColorPalette.hexValues.contains) ?? false
            return """
            create_task(missing=\(missing), extra=\(extra), \
            iconAllowed=\(iconIsAllowed), colorAllowed=\(colorIsAllowed))
            """
        }.joined(separator: "; ")
    }

    func verifyGeneratedWorkspace(
        _ workspace: AITaskWorkspaceSnapshot,
        expectedChecklistCount: Int
    ) throws -> UUID {
        XCTAssertEqual(workspace.categories.count, 1)
        XCTAssertEqual(workspace.tasks.count, 1)
        XCTAssertEqual(
            workspace.checklistItems.count,
            expectedChecklistCount
        )

        let category = try XCTUnwrap(
            workspace.categories.first { $0.title == "阅读" }
        )
        let task = try XCTUnwrap(
            workspace.tasks.first { $0.title == "人工智能：现代方法" }
        )
        XCTAssertEqual(task.categoryID, category.id)
        XCTAssertNil(task.parentID)

        let checklistItems = workspace.checklistItems
            .filter { $0.taskID == task.id }
            .sorted {
                if $0.sortOrder != $1.sortOrder {
                    return $0.sortOrder < $1.sortOrder
                }
                return $0.id.uuidString < $1.id.uuidString
            }
        XCTAssertEqual(checklistItems.count, expectedChecklistCount)
        XCTAssertEqual(
            checklistItems.compactMap {
                Self.singleOrdinal(in: $0.title)
            },
            Array(1 ... expectedChecklistCount)
        )
        return task.id
    }

    static func singleOrdinal(in title: String) -> Int? {
        let ordinals = title.split { character in
            character.isNumber == false
        }.compactMap { Int($0) }
        guard ordinals.count == 1 else { return nil }
        return ordinals[0]
    }
}
