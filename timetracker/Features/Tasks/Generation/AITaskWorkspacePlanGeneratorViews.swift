import SwiftUI

struct AITaskPlanGeneratorSheet: View {
    private enum PendingDiscardAction {
        case dismissSheet
        case returnToRequest
    }

    let store: TimeTrackerStore
    let onConfigureAI: () -> Void
    let onApply: (AITaskWorkspaceReviewDraft) async -> AITaskWorkspaceApplyResult

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dismiss) private var dismiss
    @State private var model: AITaskPlanGenerationModel
    @State private var requestText = ""
    @State private var pendingDiscardAction: PendingDiscardAction?
    @State private var isDiscardConfirmationPresented = false
    @State private var isDestructiveConfirmationPresented = false

    init(
        store: TimeTrackerStore,
        onConfigureAI: @escaping () -> Void,
        onApply: @escaping (AITaskWorkspaceReviewDraft) async -> AITaskWorkspaceApplyResult
    ) {
        self.store = store
        self.onConfigureAI = onConfigureAI
        self.onApply = onApply
        _model = State(initialValue: AITaskPlanGenerationModel(store: store))
    }

    private var isConfigured: Bool {
        store.preferences.isLLMConfigured
    }

    private var isGenerating: Bool {
        model.isGenerating
    }

    private var isApplying: Bool {
        model.isApplying
    }

    private var hasUnsavedChanges: Bool {
        requestText.isEmpty == false || model.reviewDraft != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if let reviewDraft = model.reviewDraft {
                    AITaskWorkspaceReviewView(
                        draft: reviewDraft,
                        errorMessage: model.errorMessage,
                        isApplying: isApplying,
                        onChangeRequest: requestReturnToRequest
                    )
                } else {
                    requestForm
                }
            }
            .animation(
                reduceMotion ? nil : AppMotion.stateChange,
                value: model.reviewDraft == nil
            )
            .navigationTitle(AppStrings.localized("aiTaskPlan.title"))
            .appInlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel, action: requestDismiss)
                        .disabled(isApplying)
                        .accessibilityIdentifier("aiTaskPlan.cancel")
                }

                if let reviewDraft = model.reviewDraft {
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
            if let reviewDraft = model.reviewDraft {
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
        .task {
            await model.loadDisclosureCounts()
        }
        .onDisappear {
            model.cancel()
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
                                if let generationProgress = model.progress {
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
                                action: model.stop
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
        if let errorMessage = model.errorMessage {
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
        guard let disclosedCounts = model.disclosedCounts else {
            return AppStrings.localized("aiTaskPlan.privacy.loading")
        }
        return String.localizedStringWithFormat(
            AppStrings.localized("aiTaskPlan.privacy.countsFormat"),
            Int64(disclosedCounts.categoryCount),
            Int64(disclosedCounts.taskCount),
            Int64(disclosedCounts.checklistCount)
        )
    }

    private func generate() {
        model.generate(request: requestText)
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
        model.apply(draft, using: onApply, onApplied: { dismiss() })
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
            model.cancel()
            dismiss()
        case .returnToRequest:
            model.discardReview()
        case nil:
            break
        }
    }
}
