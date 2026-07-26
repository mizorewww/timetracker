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
        try await LLMTaskWorkspacePlanningService().generate(
            request: prompt,
            instructions: LLMTaskPlanPrompt.defaultInstructions,
            workspace: workspace,
            endpoint: configuration.endpoint,
            apiKey: configuration.apiKey,
            modelID: configuration.modelID
        )
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
