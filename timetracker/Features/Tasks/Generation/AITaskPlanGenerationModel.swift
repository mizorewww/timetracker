import Foundation
import Observation

/// Owns the AI plan sheet's generate/apply lifetimes. At most one model
/// request or apply runs at a time; starting a new one cancels the previous.
@MainActor
@Observable
final class AITaskPlanGenerationModel {
    enum Phase: Equatable {
        case idle
        case generating
        case applying
    }

    typealias CaptureBaseline = @MainActor () async throws -> AITaskAtomicMutationBaseline
    typealias GeneratePlan = @MainActor (
        _ request: String,
        _ workspace: AITaskWorkspaceSnapshot,
        _ onProgress: @escaping @MainActor @Sendable (LLMGenerationProgress) -> Void
    ) async throws -> LLMTaskWorkspacePlan

    private(set) var phase = Phase.idle
    private(set) var progress: LLMGenerationProgress?
    private(set) var disclosedCounts: AITaskWorkspaceCounts?
    private(set) var reviewDraft: AITaskWorkspaceReviewDraft?
    var errorMessage: String?

    @ObservationIgnored private let captureBaseline: CaptureBaseline
    @ObservationIgnored private let generatePlan: GeneratePlan
    @ObservationIgnored private var task: Task<Void, Never>?
    /// Lets a superseded task skip resetting state that now belongs to its
    /// successor.
    @ObservationIgnored private var generation = 0

    init(captureBaseline: @escaping CaptureBaseline, generatePlan: @escaping GeneratePlan) {
        self.captureBaseline = captureBaseline
        self.generatePlan = generatePlan
    }

    convenience init(store: TimeTrackerStore) {
        self.init(
            captureBaseline: { try await store.captureAITaskWorkspaceBaseline() },
            generatePlan: { request, workspace, onProgress in
                try await LLMTaskWorkspacePlanningService().generate(
                    request: request,
                    instructions: store.preferences.llmTaskPlanInstructions,
                    workspace: workspace,
                    configuration: store.preferences.llmRequestConfiguration,
                    onProgress: onProgress
                )
            }
        )
    }

    var isGenerating: Bool {
        phase == .generating
    }

    var isApplying: Bool {
        phase == .applying
    }

    func loadDisclosureCounts() async {
        guard disclosedCounts == nil else { return }
        do {
            disclosedCounts = try await AITaskWorkspaceCounts(snapshot: captureBaseline().snapshot)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @discardableResult
    func generate(request: String) -> Task<Void, Never> {
        let generation = begin(.generating)
        errorMessage = nil
        progress = nil
        let task = Task {
            defer { finish(generation) }
            do {
                let baseline = try await captureBaseline()
                guard isCurrent(generation) else { return }
                disclosedCounts = AITaskWorkspaceCounts(snapshot: baseline.snapshot)
                let plan = try await generatePlan(request, baseline.snapshot) { progress in
                    guard self.isCurrent(generation) else { return }
                    self.progress = progress
                }
                guard isCurrent(generation) else { return }
                reviewDraft = AITaskWorkspaceReviewDraft(baseline: baseline, plan: plan)
            } catch is CancellationError {
                // Stop is a normal user action and preserves the request.
            } catch {
                guard isCurrent(generation) else { return }
                errorMessage = error.localizedDescription
            }
        }
        self.task = task
        return task
    }

    func stop() {
        cancel()
        progress = nil
    }

    /// Cancels any running request or apply and returns to idle.
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        phase = .idle
    }

    @discardableResult
    func apply(
        _ draft: AITaskWorkspaceReviewDraft,
        using onApply: @escaping (AITaskWorkspaceReviewDraft) async -> AITaskWorkspaceApplyResult,
        onApplied: @escaping @MainActor () -> Void
    ) -> Task<Void, Never>? {
        guard isApplying == false else { return nil }
        let generation = begin(.applying)
        errorMessage = nil
        let task = Task {
            let result = await onApply(draft)
            guard isCurrent(generation) else { return }
            switch result {
            case .applied:
                onApplied()
            case let .workspaceChanged(message),
                 let .failed(message):
                errorMessage = message
                finish(generation)
            }
        }
        self.task = task
        return task
    }

    func discardReview() {
        errorMessage = nil
        reviewDraft = nil
    }

    private func begin(_ phase: Phase) -> Int {
        task?.cancel()
        generation += 1
        self.phase = phase
        return generation
    }

    private func isCurrent(_ generation: Int) -> Bool {
        generation == self.generation && Task.isCancelled == false
    }

    private func finish(_ generation: Int) {
        guard generation == self.generation else { return }
        task = nil
        phase = .idle
    }
}

struct AITaskWorkspaceCounts: Equatable {
    let categoryCount: Int
    let taskCount: Int
    let checklistCount: Int

    init(snapshot: AITaskWorkspaceSnapshot) {
        categoryCount = snapshot.categories.count
        taskCount = snapshot.tasks.count
        checklistCount = snapshot.checklistItems.count
    }
}
