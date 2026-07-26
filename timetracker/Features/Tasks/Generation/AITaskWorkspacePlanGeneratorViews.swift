import MarkdownView
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

    private var usesUITestFixture: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--uitesting-ai-task-plan") ||
            CommandLine.arguments.contains("--uitesting-ai-task-plan-large")
        #else
        false
        #endif
    }

    private var usesLargeUITestFixture: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--uitesting-ai-task-plan-large")
        #else
        false
        #endif
    }

    private var isConfigured: Bool {
        usesUITestFixture ||
            (
                LLMModelService.modelsURL(
                    endpoint: store.preferences.llmEndpoint
                ) != nil &&
                    store.preferences.llmAPIKey
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty == false &&
                    store.preferences.llmAvailableModelIDs
                    .contains(store.preferences.llmSelectedModel)
            )
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
                                    Text(
                                        String.localizedStringWithFormat(
                                            AppStrings.localized(
                                                "aiTaskPlan.applyFormat"
                                            ),
                                            Int64(reviewDraft.mutationCount)
                                        )
                                    )
                                }
                            }
                            .disabled(
                                isApplying || reviewDraft.mutationCount == 0
                            )
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
                                }
                            }
                            Spacer(minLength: 8)
                            Button(
                                AppStrings.localized(
                                    "aiTaskPlan.stopGenerating"
                                ),
                                action: stopGenerating
                            )
                        }
                        .frame(
                            minHeight: AppLayout.minimumInteractiveTarget
                        )
                        .accessibilityIdentifier("aiTaskPlan.generating")
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
                let plan: LLMTaskWorkspacePlan
                if usesUITestFixture {
                    try await Task.sleep(for: .milliseconds(180))
                    plan = try AITaskWorkspaceUITestPlan.make(
                        snapshot: baseline.snapshot,
                        large: usesLargeUITestFixture
                    )
                } else {
                    plan = try await LLMTaskWorkspacePlanningService()
                        .generate(
                            request: request,
                            instructions:
                            store.preferences.llmTaskPlanInstructions,
                            workspace: baseline.snapshot,
                            endpoint: store.preferences.llmEndpoint,
                            apiKey: store.preferences.llmAPIKey,
                            modelID:
                            store.preferences.llmSelectedModel
                        ) { progress in
                            guard generationRequestID == requestID,
                                  Task.isCancelled == false
                            else {
                                return
                            }
                            generationProgress = progress
                        }
                }
                guard Task.isCancelled == false,
                      generationRequestID == requestID
                else {
                    return
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

private struct AITaskWorkspaceReviewView: View {
    let draft: AITaskWorkspaceReviewDraft
    let errorMessage: String?
    let isApplying: Bool
    let onChangeRequest: () -> Void

    var body: some View {
        List {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(.app("aiTaskPlan.preview.workspaceNotice"))
                            .font(.headline)
                        Text(draft.localizedOperationSummary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "checklist.checked")
                        .foregroundStyle(.purple)
                }
                .accessibilityIdentifier("aiTaskPlan.changeSummary")

                Button(action: onChangeRequest) {
                    Label(
                        AppStrings.localized("aiTaskPlan.editRequest"),
                        systemImage: "arrow.backward"
                    )
                }
                .disabled(isApplying)
                .accessibilityIdentifier("aiTaskPlan.editRequest")
            } footer: {
                Text(.app("aiTaskPlan.preview.workspaceFooter"))
            }

            Section(AppStrings.localized("aiTaskPlan.changes.header")) {
                ForEach(
                    Array(draft.plan.operations.enumerated()),
                    id: \.offset
                ) { index, operation in
                    AITaskWorkspaceOperationRow(
                        operation: operation,
                        index: index,
                        original: draft.plan.originalSnapshot,
                        resulting: draft.plan.resultingSnapshot
                    )
                }
            }

            if let reasoning = draft.plan.reasoningContent {
                Section {
                    DisclosureGroup {
                        ScrollView {
                            MarkdownView(reasoning)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                        }
                        .frame(maxHeight: 320)
                        .padding(.vertical, 4)
                    } label: {
                        Label(
                            AppStrings.localized(
                                "aiTaskPlan.reasoning.title"
                            ),
                            systemImage: "brain"
                        )
                    }
                    .accessibilityIdentifier("aiTaskPlan.reasoning")
                }
            }

            if let rawOutput = draft.plan.rawResponseContent {
                Section {
                    DisclosureGroup {
                        ScrollView {
                            Text(rawOutput)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(
                                    maxWidth: .infinity,
                                    alignment: .leading
                                )
                                .accessibilityIdentifier(
                                    "aiTaskPlan.rawOutput.content"
                                )
                        }
                        .frame(maxHeight: 320)
                        .padding(.vertical, 4)
                    } label: {
                        Label(
                            AppStrings.localized(
                                "aiTaskPlan.rawOutput.title"
                            ),
                            systemImage: "curlybraces"
                        )
                    }
                    .accessibilityIdentifier("aiTaskPlan.rawOutput")
                }
            }

            if draft.mutationCount == 0 {
                Section {
                    ContentUnavailableView(
                        AppStrings.localized(
                            "aiTaskPlan.noChanges.title"
                        ),
                        systemImage: "checkmark.circle",
                        description: Text(.app(
                            "aiTaskPlan.noChanges.message"
                        ))
                    )
                }
            }

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
                } footer: {
                    Text(.app("aiTaskPlan.error.previewPreserved"))
                }
            }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }
}

private struct AITaskWorkspaceOperationRow: View {
    let operation: AITaskWorkspaceOperation
    let index: Int
    let original: AITaskWorkspaceSnapshot
    let resulting: AITaskWorkspaceSnapshot

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: operation.previewSymbolName)
                .foregroundStyle(operation.previewTint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(operation.localizedKind)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(operation.previewTint)
                Text(operation.previewTitle)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(operation.previewDetail(
                    original: original,
                    resulting: resulting
                ))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("aiTaskPlan.operation.\(index)")
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

private extension AITaskWorkspaceReviewDraft {
    var mutationCount: Int {
        plan.operations.filter(\.isMutation).count
    }

    var hasDestructiveOperations: Bool {
        plan.operations.contains(where: \.isDestructive)
    }

    var localizedOperationSummary: String {
        let counts = plan.operations.reduce(
            into: AITaskWorkspaceOperationCounts()
        ) { result, operation in
            switch operation {
            case .createCategory, .createTask, .createChecklistItem:
                result.created += 1
            case .updateCategory, .updateTask, .updateChecklistItem:
                result.updated += 1
            case .archiveTask:
                result.archived += 1
            case .deleteCategory, .deleteChecklistItem:
                result.deleted += 1
            case .useExistingCategory:
                result.reused += 1
            }
        }
        return String.localizedStringWithFormat(
            AppStrings.localized("aiTaskPlan.changes.summaryFormat"),
            Int64(counts.created),
            Int64(counts.updated),
            Int64(counts.archived),
            Int64(counts.deleted),
            Int64(counts.reused)
        )
    }
}

private struct AITaskWorkspaceOperationCounts {
    var created = 0
    var updated = 0
    var archived = 0
    var deleted = 0
    var reused = 0
}

private extension AITaskWorkspaceOperation {
    var isMutation: Bool {
        if case .useExistingCategory = self {
            return false
        }
        return true
    }

    var isDestructive: Bool {
        switch self {
        case .deleteCategory, .archiveTask, .deleteChecklistItem:
            true
        case let .updateTask(before, after):
            before.quantityGoal != nil && after.quantityGoal == nil
        case .useExistingCategory,
             .createCategory,
             .updateCategory,
             .createTask,
             .createChecklistItem,
             .updateChecklistItem:
            false
        }
    }

    var localizedKind: String {
        let key = switch self {
        case .useExistingCategory:
            "aiTaskPlan.operation.reuse"
        case .createCategory, .createTask, .createChecklistItem:
            "aiTaskPlan.operation.create"
        case .updateCategory, .updateTask, .updateChecklistItem:
            "aiTaskPlan.operation.update"
        case .archiveTask:
            "aiTaskPlan.operation.archive"
        case .deleteCategory, .deleteChecklistItem:
            "aiTaskPlan.operation.delete"
        }
        return AppStrings.localized(key)
    }

    var previewSymbolName: String {
        switch self {
        case .useExistingCategory:
            "arrow.triangle.merge"
        case .createCategory, .createTask, .createChecklistItem:
            "plus.circle.fill"
        case .updateCategory, .updateTask, .updateChecklistItem:
            "pencil.circle.fill"
        case .archiveTask:
            "archivebox.fill"
        case .deleteCategory, .deleteChecklistItem:
            "trash.circle.fill"
        }
    }

    var previewTint: Color {
        switch self {
        case .archiveTask, .deleteCategory, .deleteChecklistItem:
            .red
        case .useExistingCategory:
            .teal
        case .createCategory, .createTask, .createChecklistItem:
            .green
        case .updateCategory, .updateTask, .updateChecklistItem:
            .blue
        }
    }

    var previewTitle: String {
        switch self {
        case let .useExistingCategory(categoryID):
            categoryID.uuidString
        case let .createCategory(category):
            category.title
        case let .updateCategory(_, after):
            after.title
        case let .deleteCategory(category, _):
            category.title
        case let .createTask(task):
            task.path
        case let .updateTask(_, after):
            after.path
        case let .archiveTask(before, _, _):
            before.path
        case let .createChecklistItem(item):
            item.title
        case let .updateChecklistItem(_, after):
            after.title
        case let .deleteChecklistItem(item):
            item.title
        }
    }

    func previewDetail(
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> String {
        switch self {
        case let .useExistingCategory(categoryID):
            let title = resulting.categories.first {
                $0.id == categoryID
            }?.title ?? categoryID.uuidString
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.reuseCategoryFormat"
                ),
                title
            )
        case .createCategory:
            return AppStrings.localized(
                "aiTaskPlan.operation.categoryCreated"
            )
        case let .updateCategory(before, after):
            return before.title + " → " + after.title
        case let .deleteCategory(_, affectedRootTaskIDs):
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.categoryDeleteImpactFormat"
                ),
                Int64(affectedRootTaskIDs.count)
            )
        case let .createTask(task):
            return taskContext(task, snapshot: resulting)
        case let .updateTask(before, after):
            return before.path + " → " + after.path
        case let .archiveTask(_, _, affectedDescendantIDs):
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.archiveImpactFormat"
                ),
                Int64(affectedDescendantIDs.count)
            )
        case let .createChecklistItem(item):
            return checklistContext(item, snapshot: resulting)
        case let .updateChecklistItem(before, after):
            return checklistContext(
                after,
                snapshot: resulting
            ) + "\n" + before.title + " → " + after.title
        case let .deleteChecklistItem(item):
            return checklistContext(item, snapshot: original)
        }
    }

    func taskContext(
        _ task: AITaskWorkspaceTask,
        snapshot: AITaskWorkspaceSnapshot
    ) -> String {
        if let categoryID = task.categoryID,
           let category = snapshot.categories.first(where: {
               $0.id == categoryID
           })
        {
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.taskCategoryFormat"
                ),
                category.title
            )
        }
        return AppStrings.localized("aiTaskPlan.uncategorized")
    }

    func checklistContext(
        _ item: AITaskWorkspaceChecklistItem,
        snapshot: AITaskWorkspaceSnapshot
    ) -> String {
        let path = snapshot.tasks.first {
            $0.id == item.taskID
        }?.path ?? item.taskID.uuidString
        return String.localizedStringWithFormat(
            AppStrings.localized(
                "aiTaskPlan.operation.checklistTaskFormat"
            ),
            path
        )
    }
}

@MainActor
private enum AITaskWorkspaceUITestPlan {
    static func make(
        snapshot: AITaskWorkspaceSnapshot,
        large: Bool
    ) throws -> LLMTaskWorkspacePlan {
        var overlay = AITaskWorkspaceOverlay(snapshot: snapshot)
        let studyCategory = snapshot.categories.first {
            $0.title == "Study"
        }
        if studyCategory != nil {
            _ = try overlay.useExistingCategory(named: "Study")
        }

        let readingTaskID = fixedID(
            large
                ? "20000000-0000-4000-8000-000000000150"
                : "20000000-0000-4000-8000-000000000110"
        )
        _ = try overlay.createTask(
            id: readingTaskID,
            title: large ? "Read 150 Chapters" : "Read 10 Chapters",
            parentID: nil,
            categoryID: studyCategory?.id,
            notes: "A complete AI-reviewed reading plan.",
            estimatedMinutes: large ? 900 : 300,
            dueAt: nil,
            iconName: "book",
            colorHex: "16A34A"
        )
        let checklistCount = large ? 150 : 10
        for index in 1 ... checklistCount {
            _ = try overlay.createChecklistItem(
                id: fixedID(
                    String(
                        format:
                        "30000000-0000-4000-8000-%012d",
                        index
                    )
                ),
                taskID: readingTaskID,
                title: "Chapter \(index)",
                isCompleted: false,
                iconName: "book.pages",
                colorHex: "16A34A"
            )
        }

        if large == false {
            let fitnessCategory = try overlay.createCategory(
                id: fixedID(
                    "10000000-0000-4000-8000-000000000101"
                ),
                title: "Fitness Plan",
                iconName: "figure.strengthtraining.traditional",
                colorHex: "F97316"
            )
            _ = try overlay.createTask(
                id: fixedID(
                    "20000000-0000-4000-8000-000000000101"
                ),
                title: "Daily Push-ups",
                parentID: nil,
                categoryID: fitnessCategory.id,
                notes: "",
                estimatedMinutes: 10,
                dueAt: nil,
                iconName: "figure.strengthtraining.traditional",
                colorHex: "F97316",
                quantityGoal: TaskQuantityGoalDraft(
                    targetAmount: 50,
                    unitLabel: "push-ups"
                ),
                dailyRecurrence: TaskDailyRecurrenceDraft(
                    startingAt: Date(),
                    timeZone: .current
                )
            )

            if let task = snapshot.tasks.first(where: {
                $0.title == "Read Apple HIG"
            }) {
                _ = try overlay.updateTask(
                    id: task.id,
                    title: "Read Apple HIG Carefully",
                    parentID: task.parentID,
                    categoryID: task.categoryID,
                    notes: task.notes,
                    estimatedMinutes: task.estimatedMinutes,
                    dueAt: task.dueAt,
                    iconName: task.iconName,
                    colorHex: task.colorHex,
                    quantityGoal: task.quantityGoal,
                    dailyRecurrence: task.dailyRecurrence
                )
            }
            if let task = snapshot.tasks.first(where: {
                $0.title == "SwiftData Docs"
            }) {
                _ = try overlay.deleteTask(id: task.id)
            }
            if let item = snapshot.checklistItems.first {
                _ = try overlay.deleteChecklistItem(id: item.id)
            }
        }

        return LLMTaskWorkspacePlan(
            originalSnapshot: snapshot,
            resultingSnapshot: overlay.snapshot,
            operations: overlay.operations,
            modelID: "ui-test-model",
            reasoningContent:
            "The plan reuses the existing Study category and previews every change before applying it.",
            rawResponseContent:
            #"{"tool_calls":[{"name":"create_task","title":"Read 10 Chapters"}]}"#,
            toolRoundCount: 3,
            toolCallCount: overlay.operations.count + 1
        )
    }

    static func fixedID(_ value: String) -> UUID {
        guard let id = UUID(uuidString: value) else {
            preconditionFailure("Invalid UI test UUID")
        }
        return id
    }
}
