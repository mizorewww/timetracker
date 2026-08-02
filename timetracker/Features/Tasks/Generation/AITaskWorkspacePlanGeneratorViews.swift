import SwiftUI

struct AITaskPlanGeneratorSheet: View {
    private enum PendingDiscardAction {
        case dismissSheet
        case returnToRequest
    }

    let store: TimeTrackerStore
    let onConfigureAI: () -> Void
    let onApply: (AITaskWorkspaceReviewDraft) -> AITaskWorkspaceApplyResult

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var requestText = ""
    @State private var reviewDraft: AITaskWorkspaceReviewDraft?
    @State private var disclosedCounts: AITaskWorkspaceCounts?
    @State private var generationTask: Task<Void, Never>?
    @State private var generationRequestID = UUID()
    @State private var generationProgress: LLMGenerationProgress?
    @State private var isGenerating = false
    @State private var isApplying = false
    @State private var errorMessage: String?
    @State private var pendingDiscardAction: PendingDiscardAction?
    @State private var isDiscardConfirmationPresented = false
    @State private var isDestructiveConfirmationPresented = false

    private var isConfigured: Bool {
        LLMModelService.modelsURL(
            endpoint: store.preferences.llmEndpoint
        ) != nil &&
            store.preferences.llmAPIKey
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == false &&
            store.preferences.llmAvailableModelIDs
            .contains(store.preferences.llmSelectedModel)
    }

    private var hasUnsavedChanges: Bool {
        requestText.isEmpty == false || reviewDraft != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let reviewDraft {
                    AITaskWorkspaceReviewView(
                        draft: reviewDraft,
                        errorMessage: errorMessage,
                        isApplying: isApplying,
                        onChangeRequest: requestReturnToRequest
                    )
                } else {
                    requestForm
                }
            }
            .navigationTitle(AppStrings.localized("aiTaskPlan.title"))
            #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
            #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(AppStrings.cancel, action: requestDismiss)
                            .disabled(isApplying)
                            .accessibilityIdentifier("aiTaskPlan.cancel")
                    }

                    if let reviewDraft {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                requestApply(reviewDraft)
                            } label: {
                                if isApplying {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(.app("aiTaskPlan.apply"))
                                }
                            }
                            .accessibilityLabel(
                                String.localizedStringWithFormat(
                                    AppStrings.localized(
                                        "aiTaskPlan.applyFormat"
                                    ),
                                    Int64(reviewDraft.mutationCount)
                                )
                            )
                            .disabled(
                                isApplying || reviewDraft.mutationCount == 0
                            )
                            #if os(macOS)
                            .controlSize(.large)
                            #endif
                            .accessibilityIdentifier("aiTaskPlan.apply")
                        }
                    } else if isConfigured {
                        ToolbarItem(placement: .confirmationAction) {
                            Button(
                                AppStrings.localized("aiTaskPlan.generate"),
                                action: generate
                            )
                            .disabled(
                                isGenerating ||
                                    requestText
                                    .trimmingCharacters(
                                        in: .whitespacesAndNewlines
                                    )
                                    .isEmpty
                            )
                            .accessibilityIdentifier("aiTaskPlan.generate")
                        }
                    }
                }
        }
        .platformSheetFrame(width: 720, height: 760)
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: hasUnsavedChanges || isApplying,
            discard: performPendingDiscard
        )
        .confirmationDialog(
            AppStrings.localized("aiTaskPlan.destructive.title"),
            isPresented: $isDestructiveConfirmationPresented,
            titleVisibility: .visible
        ) {
            if let reviewDraft {
                Button(
                    String.localizedStringWithFormat(
                        AppStrings.localized(
                            "aiTaskPlan.destructive.applyFormat"
                        ),
                        Int64(reviewDraft.mutationCount)
                    ),
                    role: .destructive
                ) {
                    apply(reviewDraft)
                }
                .accessibilityIdentifier("aiTaskPlan.destructive.confirm")
            }
            Button(AppStrings.cancel, role: .cancel) {}
                .accessibilityIdentifier("aiTaskPlan.destructive.cancel")
        } message: {
            Text(.app("aiTaskPlan.destructive.message"))
        }
        .onAppear(perform: refreshDisclosureCounts)
        .onDisappear {
            generationTask?.cancel()
        }
        .accessibilityIdentifier("aiTaskPlan.sheet")
    }

    private var requestForm: some View {
        Form {
            if isConfigured {
                Section {
                    TextEditor(text: $requestText)
                        .font(.body)
                        .frame(minHeight: 150)
                        .disabled(isGenerating)
                        .accessibilityLabel(
                            AppStrings.localized("aiTaskPlan.request.label")
                        )
                        .accessibilityIdentifier("aiTaskPlan.request")
                } header: {
                    Text(.app("aiTaskPlan.request.header"))
                } footer: {
                    Text(.app("aiTaskPlan.request.footer"))
                }

                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(.app("aiTaskPlan.privacy.title"))
                                .font(.headline)
                            Text(disclosureSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "network")
                            .foregroundStyle(.purple)
                    }
                    .accessibilityIdentifier("aiTaskPlan.privacy")

                    Label(
                        AppStrings.localized("aiTaskPlan.privacy.excluded"),
                        systemImage: "lock.shield"
                    )
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                } footer: {
                    Text(.app("aiTaskPlan.privacy.footer"))
                }

                if isGenerating {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityIdentifier(
                                    "aiTaskPlan.generating"
                                )
                            VStack(alignment: .leading, spacing: 2) {
                                Text(.app("aiTaskPlan.generating.workspace"))
                                if let generationProgress {
                                    Text(
                                        String.localizedStringWithFormat(
                                            AppStrings.localized(
                                                "aiTaskPlan.generating.tokens"
                                            ),
                                            Int64(
                                                generationProgress
                                                    .displayedOutputTokens
                                            )
                                        )
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                    .accessibilityIdentifier(
                                        "aiTaskPlan.generating.tokens"
                                    )
                                }
                            }
                            Spacer(minLength: 8)
                            Button(
                                AppStrings.localized(
                                    "aiTaskPlan.stopGenerating"
                                ),
                                action: stopGenerating
                            )
                            .accessibilityIdentifier(
                                "aiTaskPlan.stopGenerating"
                            )
                        }
                        .frame(
                            minHeight: AppLayout.minimumInteractiveTarget
                        )
                    }
                }

                requestErrorSection
            } else {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(.app(
                                "aiTaskPlan.configurationRequired.title"
                            ))
                            .font(.headline)
                            Text(.app(
                                "aiTaskPlan.configurationRequired.message"
                            ))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                    }

                    Button(action: onConfigureAI) {
                        Label(
                            AppStrings.localized(
                                "aiTaskPlan.configureAI"
                            ),
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    .accessibilityIdentifier("aiTaskPlan.configureAI")
                }
            }
        }
        .formStyle(.grouped)
    }

    @ViewBuilder
    private var requestErrorSection: some View {
        if let errorMessage {
            Section {
                Label(
                    errorMessage,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.red)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityIdentifier("aiTaskPlan.error")

                if isGenerating == false {
                    Button(
                        AppStrings.localized("aiTaskPlan.retry"),
                        action: generate
                    )
                    .accessibilityIdentifier("aiTaskPlan.retry")
                }
            }
        }
    }

    private var disclosureSummary: String {
        guard let disclosedCounts else {
            return AppStrings.localized("aiTaskPlan.privacy.loading")
        }
        return String.localizedStringWithFormat(
            AppStrings.localized("aiTaskPlan.privacy.countsFormat"),
            Int64(disclosedCounts.categoryCount),
            Int64(disclosedCounts.taskCount),
            Int64(disclosedCounts.checklistCount)
        )
    }

    private func refreshDisclosureCounts() {
        guard disclosedCounts == nil else { return }
        do {
            disclosedCounts = try AITaskWorkspaceCounts(
                snapshot: store.captureAITaskWorkspaceBaseline().snapshot
            )
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func generate() {
        generationTask?.cancel()
        let request = requestText
        let requestID = UUID()
        generationRequestID = requestID
        errorMessage = nil
        generationProgress = nil
        isGenerating = true

        generationTask = Task { @MainActor in
            let progressClock = ContinuousClock()
            var firstProgressInstant: ContinuousClock.Instant?
            defer {
                if generationRequestID == requestID {
                    isGenerating = false
                    generationTask = nil
                }
            }
            do {
                let baseline = try store.captureAITaskWorkspaceBaseline()
                disclosedCounts = AITaskWorkspaceCounts(
                    snapshot: baseline.snapshot
                )
                let plan = try await LLMTaskWorkspacePlanningService()
                    .generate(
                        request: request,
                        instructions:
                        store.preferences.llmTaskPlanInstructions,
                        workspace: baseline.snapshot,
                        endpoint: store.preferences.llmEndpoint,
                        apiKey: store.preferences.llmAPIKey,
                        modelID:
                        store.preferences.llmSelectedModel,
                        reasoningEffort:
                        store.preferences.llmReasoningEffort,
                        onProgress: { progress in
                            guard generationRequestID == requestID,
                                  Task.isCancelled == false
                            else {
                                return
                            }
                            if firstProgressInstant == nil {
                                firstProgressInstant = progressClock.now
                            }
                            generationProgress = progress
                        }
                    )
                guard Task.isCancelled == false,
                      generationRequestID == requestID
                else {
                    return
                }
                if let firstProgressInstant {
                    let minimumPresentationDuration =
                        Duration.seconds(2)
                    let elapsed = firstProgressInstant.duration(
                        to: progressClock.now
                    )
                    if elapsed < minimumPresentationDuration {
                        try await progressClock.sleep(
                            for: minimumPresentationDuration - elapsed
                        )
                    }
                }
                withAnimation(
                    reduceMotion ? nil : .snappy(duration: 0.22)
                ) {
                    reviewDraft = AITaskWorkspaceReviewDraft(
                        baseline: baseline,
                        plan: plan
                    )
                }
            } catch is CancellationError {
                // Stop is a normal user action and preserves the request.
            } catch {
                guard Task.isCancelled == false,
                      generationRequestID == requestID
                else {
                    return
                }
                errorMessage = error.localizedDescription
            }
        }
    }

    private func stopGenerating() {
        generationRequestID = UUID()
        generationTask?.cancel()
        generationTask = nil
        generationProgress = nil
        isGenerating = false
    }

    private func requestApply(_ draft: AITaskWorkspaceReviewDraft) {
        guard draft.mutationCount > 0 else { return }
        if draft.hasDestructiveOperations {
            isDestructiveConfirmationPresented = true
        } else {
            apply(draft)
        }
    }

    private func apply(_ draft: AITaskWorkspaceReviewDraft) {
        guard isApplying == false else { return }
        isApplying = true
        errorMessage = nil
        switch onApply(draft) {
        case .applied:
            dismiss()
        case let .workspaceChanged(message),
             let .failed(message):
            errorMessage = message
            isApplying = false
        }
    }

    private func requestDismiss() {
        guard hasUnsavedChanges else {
            dismiss()
            return
        }
        pendingDiscardAction = .dismissSheet
        isDiscardConfirmationPresented = true
    }

    private func requestReturnToRequest() {
        pendingDiscardAction = .returnToRequest
        isDiscardConfirmationPresented = true
    }

    private func performPendingDiscard() {
        let action = pendingDiscardAction
        pendingDiscardAction = nil
        isDiscardConfirmationPresented = false
        switch action {
        case .dismissSheet:
            generationTask?.cancel()
            dismiss()
        case .returnToRequest:
            errorMessage = nil
            withAnimation(
                reduceMotion ? nil : .snappy(duration: 0.22)
            ) {
                reviewDraft = nil
            }
        case nil:
            break
        }
    }
}

private struct AITaskWorkspaceCounts: Equatable {
    let categoryCount: Int
    let taskCount: Int
    let checklistCount: Int

    init(snapshot: AITaskWorkspaceSnapshot) {
        categoryCount = snapshot.categories.count
        taskCount = snapshot.tasks.count
        checklistCount = snapshot.checklistItems.count
    }
}
