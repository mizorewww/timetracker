import Foundation
import Testing
@testable import timetracker

@MainActor
struct AITaskPlanGenerationModelTests {
    @Test
    func finishedGenerationPublishesTheReviewWithoutAnArtificialDelay() async {
        let model = AITaskPlanGenerationModel(
            captureBaseline: { Self.baseline },
            generatePlan: { _, workspace, onProgress in
                onProgress(LLMGenerationProgress(
                    contentCharacterCount: 4,
                    reasoningCharacterCount: 0,
                    reportedCompletionTokens: nil
                ))
                return Self.plan(for: workspace)
            }
        )

        await model.generate(request: "Plan my week").value

        #expect(model.reviewDraft?.plan == Self.plan(for: Self.baseline.snapshot))
        #expect(model.disclosedCounts == AITaskWorkspaceCounts(snapshot: Self.baseline.snapshot))
        #expect(model.progress != nil)
        #expect(model.phase == .idle)
        #expect(model.errorMessage == nil)
    }

    @Test
    func failedGenerationReportsTheErrorAndKeepsTheRequestForm() async {
        let model = AITaskPlanGenerationModel(
            captureBaseline: { Self.baseline },
            generatePlan: { _, _, _ in throw LLMClientError.timeout }
        )

        await model.generate(request: "Plan my week").value

        #expect(model.reviewDraft == nil)
        #expect(model.errorMessage == LLMClientError.timeout.localizedDescription)
        #expect(model.phase == .idle)
    }

    @Test
    func failedApplyReturnsToReviewWithItsMessage() async throws {
        let model = AITaskPlanGenerationModel(
            captureBaseline: { Self.baseline },
            generatePlan: { _, workspace, _ in Self.plan(for: workspace) }
        )
        await model.generate(request: "Plan my week").value
        let draft = try #require(model.reviewDraft)
        var didApply = false

        await model.apply(
            draft,
            using: { _ in .workspaceChanged(message: "changed") },
            onApplied: { didApply = true }
        )?.value

        #expect(didApply == false)
        #expect(model.errorMessage == "changed")
        #expect(model.phase == .idle)
        #expect(model.reviewDraft == draft)
    }

    private static let baseline = AITaskAtomicMutationBaseline(
        snapshot: AITaskWorkspaceSnapshot(
            categories: [],
            tasks: [],
            checklistItems: []
        ),
        workspace: AITaskWorkspaceMutationBaselines(
            categoryMutationIDs: [:],
            taskMutationIDs: [:],
            categoryAssignmentMutationIDsByTaskID: [:],
            checklistItemMutationIDs: [:],
            checklistVisualMutationIDsByItemID: [:]
        ),
        quantityGoalMutationIDs: [:],
        recurrenceRuleMutationIDs: [:]
    )

    private static func plan(for workspace: AITaskWorkspaceSnapshot) -> LLMTaskWorkspacePlan {
        LLMTaskWorkspacePlan(
            originalSnapshot: workspace,
            resultingSnapshot: workspace,
            operations: [],
            modelID: "model",
            reasoningContent: nil,
            rawResponseContent: nil,
            toolRoundCount: 1,
            toolCallCount: 1
        )
    }
}
