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
                            store.preferences.llmSelectedModel,
                            onProgress: { progress in
                                guard generationRequestID == requestID,
                                      Task.isCancelled == false
                                else {
                                    return
                                }
                                generationProgress = progress
                            }
                        )
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
    private let operationPresentations:
        [AITaskWorkspaceOperationPresentation]

    init(
        draft: AITaskWorkspaceReviewDraft,
        errorMessage: String?,
        isApplying: Bool,
        onChangeRequest: @escaping () -> Void
    ) {
        self.draft = draft
        self.errorMessage = errorMessage
        self.isApplying = isApplying
        self.onChangeRequest = onChangeRequest
        operationPresentations = AITaskWorkspaceReviewPresentation(
            operations: draft.plan.operations,
            original: draft.plan.originalSnapshot,
            resulting: draft.plan.resultingSnapshot
        ).operations
    }

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
                ForEach(operationPresentations) { presentation in
                    AITaskWorkspaceOperationRow(
                        presentation: presentation
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
    let presentation: AITaskWorkspaceOperationPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: presentation.operation.previewSymbolName)
                .foregroundStyle(presentation.operation.previewTint)
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.operation.localizedKind)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(presentation.operation.previewTint)
                Text(presentation.title)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                if presentation.context.isEmpty == false {
                    Text(presentation.context)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if presentation.fieldChanges.isEmpty == false {
                    AITaskWorkspaceFieldChangesView(
                        changes: presentation.fieldChanges
                    )
                    .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityIdentifier(
            "aiTaskPlan.operation.\(presentation.accessibilityIndex)"
        )
    }
}

private struct AITaskWorkspaceFieldChangesView: View {
    let changes: [AITaskWorkspaceFieldChange]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(changes) { change in
                VStack(alignment: .leading, spacing: 3) {
                    Text(change.field.localizedTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    AITaskWorkspaceDiffValueView(
                        label: AppStrings.localized(
                            "aiTaskPlan.diff.before"
                        ),
                        value: change.before
                    )
                    AITaskWorkspaceDiffValueView(
                        label: AppStrings.localized(
                            "aiTaskPlan.diff.after"
                        ),
                        value: change.after
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AITaskWorkspaceDiffValueView: View {
    let label: String
    let value: AITaskWorkspacePreviewValue

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.tertiary)
            valueContent
                .font(.subheadline)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var valueContent: some View {
        switch value {
        case let .icon(iconName):
            Label(value.localizedText, systemImage: iconName)
        case let .color(colorHex):
            Label {
                Text(value.localizedText)
            } icon: {
                Circle()
                    .fill(Color(hex: colorHex) ?? .secondary)
                    .frame(width: 10, height: 10)
            }
        case .text,
             .optionalText,
             .minutes,
             .date,
             .boolean,
             .quantityGoal,
             .recurrence:
            Text(value.localizedText)
        }
    }
}

struct AITaskWorkspaceReviewPresentation: Equatable {
    let operations: [AITaskWorkspaceOperationPresentation]

    init(
        operations: [AITaskWorkspaceOperation],
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) {
        var occurrences:
            [AITaskWorkspaceOperationPresentation.IdentitySeed: Int] = [:]
        self.operations = operations.enumerated().map { index, operation in
            let seed = operation.presentationIdentitySeed
            let occurrence = occurrences[seed, default: 0]
            occurrences[seed] = occurrence + 1
            return AITaskWorkspaceOperationPresentation(
                id: .init(seed: seed, occurrence: occurrence),
                accessibilityIndex: index,
                operation: operation,
                original: original,
                resulting: resulting
            )
        }
    }
}

struct AITaskWorkspaceOperationPresentation: Identifiable, Equatable {
    struct IdentitySeed: Hashable {
        let kind: Kind
        let entityID: UUID
    }

    struct ID: Hashable {
        let seed: IdentitySeed
        let occurrence: Int
    }

    enum Kind: Hashable {
        case reuseCategory
        case createCategory
        case updateCategory
        case deleteCategory
        case createTask
        case updateTask
        case archiveTask
        case createChecklistItem
        case updateChecklistItem
        case deleteChecklistItem
    }

    let id: ID
    let accessibilityIndex: Int
    let operation: AITaskWorkspaceOperation
    let title: String
    let context: String
    let fieldChanges: [AITaskWorkspaceFieldChange]

    var accessibilityLabel: String {
        var components = [operation.localizedKind, title]
        if context.isEmpty == false {
            components.append(context)
        }
        for change in fieldChanges {
            components.append(change.field.localizedTitle)
            components.append(
                "\(AppStrings.localized("aiTaskPlan.diff.before")): " +
                    change.before.localizedText
            )
            components.append(
                "\(AppStrings.localized("aiTaskPlan.diff.after")): " +
                    change.after.localizedText
            )
        }
        return components.joined(separator: ", ")
    }

    init(
        id: ID,
        accessibilityIndex: Int,
        operation: AITaskWorkspaceOperation,
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) {
        self.id = id
        self.accessibilityIndex = accessibilityIndex
        self.operation = operation
        title = operation.previewTitle(
            original: original,
            resulting: resulting
        )
        context = operation.previewContext(
            original: original,
            resulting: resulting
        )
        fieldChanges = operation.fieldChanges(
            original: original,
            resulting: resulting
        )
    }
}

enum AITaskWorkspacePreviewField: String, Hashable, Identifiable {
    case title
    case path
    case category
    case notes
    case estimatedTime
    case dueDate
    case icon
    case color
    case forecast
    case quantityGoal
    case recurrence
    case completion

    var id: Self {
        self
    }

    var localizedTitle: String {
        AppStrings.localized("aiTaskPlan.diff.field.\(rawValue)")
    }
}

struct AITaskWorkspaceFieldChange: Equatable, Identifiable {
    let field: AITaskWorkspacePreviewField
    let before: AITaskWorkspacePreviewValue
    let after: AITaskWorkspacePreviewValue

    var id: AITaskWorkspacePreviewField {
        field
    }
}

enum AITaskWorkspacePreviewValue: Equatable {
    case text(String)
    case optionalText(String?)
    case minutes(Int?)
    case date(Date?)
    case boolean(Bool)
    case icon(String)
    case color(String)
    case quantityGoal(TaskQuantityGoalDraft?)
    case recurrence(TaskDailyRecurrenceDraft?)

    var localizedText: String {
        switch self {
        case let .text(value):
            return value.isEmpty
                ? AppStrings.localized("common.none")
                : value
        case let .optionalText(value):
            return value ?? AppStrings.localized("common.none")
        case let .minutes(value):
            guard let value else {
                return AppStrings.localized("common.none")
            }
            return String.localizedStringWithFormat(
                AppStrings.localized("common.minutes"),
                value
            )
        case let .date(value):
            guard let value else {
                return AppStrings.localized("common.none")
            }
            return value.formatted(
                .dateTime
                    .year()
                    .month(.abbreviated)
                    .day()
                    .hour()
                    .minute()
            )
        case let .boolean(value):
            return AppStrings.localized(
                value
                    ? "aiTaskPlan.diff.value.yes"
                    : "aiTaskPlan.diff.value.no"
            )
        case let .icon(value):
            return value
        case let .color(value):
            return TaskColorPalette.accessibilityName(for: value)
        case let .quantityGoal(value):
            guard let value else {
                return AppStrings.localized("common.none")
            }
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.diff.value.quantityGoalFormat"
                ),
                Int64(value.targetAmount),
                value.unitLabel
            )
        case let .recurrence(value):
            guard let value else {
                return AppStrings.localized("common.none")
            }
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.diff.value.recurrenceFormat"
                ),
                AppStrings.localized("task.recurrence.editor.everyDay"),
                AppStrings.localized(
                    value.isEnabled
                        ? "aiTaskPlan.diff.value.active"
                        : "aiTaskPlan.diff.value.paused"
                ),
                value.startDayKey,
                value.timeZoneIdentifier
            )
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

    var presentationIdentitySeed:
        AITaskWorkspaceOperationPresentation.IdentitySeed
    {
        let kind: AITaskWorkspaceOperationPresentation.Kind
        let entityID: UUID
        switch self {
        case let .useExistingCategory(categoryID):
            kind = .reuseCategory
            entityID = categoryID
        case let .createCategory(category):
            kind = .createCategory
            entityID = category.id
        case let .updateCategory(before, _):
            kind = .updateCategory
            entityID = before.id
        case let .deleteCategory(category, _):
            kind = .deleteCategory
            entityID = category.id
        case let .createTask(task):
            kind = .createTask
            entityID = task.id
        case let .updateTask(before, _):
            kind = .updateTask
            entityID = before.id
        case let .archiveTask(before, _, _):
            kind = .archiveTask
            entityID = before.id
        case let .createChecklistItem(item):
            kind = .createChecklistItem
            entityID = item.id
        case let .updateChecklistItem(before, _):
            kind = .updateChecklistItem
            entityID = before.id
        case let .deleteChecklistItem(item):
            kind = .deleteChecklistItem
            entityID = item.id
        }
        return AITaskWorkspaceOperationPresentation.IdentitySeed(
            kind: kind,
            entityID: entityID
        )
    }

    func previewTitle(
        original _: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> String {
        switch self {
        case let .useExistingCategory(categoryID):
            resulting.categories.first {
                $0.id == categoryID
            }?.title ?? AppStrings.localized(
                "aiTaskPlan.diff.value.unavailable"
            )
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

    func previewContext(
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> String {
        switch self {
        case let .useExistingCategory(categoryID):
            let title = resulting.categories.first {
                $0.id == categoryID
            }?.title ?? AppStrings.localized(
                "aiTaskPlan.diff.value.unavailable"
            )
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
        case .updateCategory:
            return ""
        case let .deleteCategory(_, affectedRootTaskIDs):
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.categoryDeleteImpactFormat"
                ),
                Int64(affectedRootTaskIDs.count)
            )
        case let .createTask(task):
            return taskContext(task, snapshot: resulting)
        case let .updateTask(_, after):
            return taskContext(after, snapshot: resulting)
        case let .archiveTask(_, _, affectedDescendantIDs):
            return String.localizedStringWithFormat(
                AppStrings.localized(
                    "aiTaskPlan.operation.archiveImpactFormat"
                ),
                Int64(affectedDescendantIDs.count)
            )
        case let .createChecklistItem(item):
            return checklistContext(item, snapshot: resulting)
        case let .updateChecklistItem(_, after):
            return checklistContext(after, snapshot: resulting)
        case let .deleteChecklistItem(item):
            return checklistContext(item, snapshot: original)
        }
    }

    func fieldChanges(
        original: AITaskWorkspaceSnapshot,
        resulting: AITaskWorkspaceSnapshot
    ) -> [AITaskWorkspaceFieldChange] {
        var changes: [AITaskWorkspaceFieldChange] = []
        switch self {
        case let .updateCategory(before, after):
            changes.append(
                field: .title,
                before: .text(before.title),
                after: .text(after.title)
            )
            changes.append(
                field: .icon,
                before: .icon(before.iconName),
                after: .icon(after.iconName)
            )
            changes.append(
                field: .color,
                before: .color(before.colorHex),
                after: .color(after.colorHex)
            )
            changes.append(
                field: .forecast,
                before: .boolean(before.includesInForecast),
                after: .boolean(after.includesInForecast)
            )
        case let .updateTask(before, after):
            changes.append(
                field: .title,
                before: .text(before.title),
                after: .text(after.title)
            )
            if before.parentID != after.parentID ||
                before.path != after.path
            {
                changes.append(
                    AITaskWorkspaceFieldChange(
                        field: .path,
                        before: .text(before.path),
                        after: .text(after.path)
                    )
                )
            }
            if before.categoryID != after.categoryID {
                changes.append(
                    AITaskWorkspaceFieldChange(
                        field: .category,
                        before: categoryValue(
                            id: before.categoryID,
                            snapshot: original
                        ),
                        after: categoryValue(
                            id: after.categoryID,
                            snapshot: resulting
                        )
                    )
                )
            }
            changes.append(
                field: .notes,
                before: .text(before.notes),
                after: .text(after.notes)
            )
            changes.append(
                field: .estimatedTime,
                before: .minutes(before.estimatedMinutes),
                after: .minutes(after.estimatedMinutes)
            )
            changes.append(
                field: .dueDate,
                before: .date(before.dueAt),
                after: .date(after.dueAt)
            )
            changes.append(
                field: .icon,
                before: .icon(before.iconName),
                after: .icon(after.iconName)
            )
            changes.append(
                field: .color,
                before: .color(before.colorHex),
                after: .color(after.colorHex)
            )
            changes.append(
                field: .quantityGoal,
                before: .quantityGoal(before.quantityGoal),
                after: .quantityGoal(after.quantityGoal)
            )
            changes.append(
                field: .recurrence,
                before: .recurrence(before.dailyRecurrence),
                after: .recurrence(after.dailyRecurrence)
            )
        case let .updateChecklistItem(before, after):
            changes.append(
                field: .title,
                before: .text(before.title),
                after: .text(after.title)
            )
            changes.append(
                field: .completion,
                before: .boolean(before.isCompleted),
                after: .boolean(after.isCompleted)
            )
            changes.append(
                field: .icon,
                before: .icon(before.iconName),
                after: .icon(after.iconName)
            )
            changes.append(
                field: .color,
                before: .color(before.colorHex),
                after: .color(after.colorHex)
            )
        case .useExistingCategory,
             .createCategory,
             .deleteCategory,
             .createTask,
             .archiveTask,
             .createChecklistItem,
             .deleteChecklistItem:
            break
        }
        return changes
    }

    private func taskContext(
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

    private func checklistContext(
        _ item: AITaskWorkspaceChecklistItem,
        snapshot: AITaskWorkspaceSnapshot
    ) -> String {
        let path = snapshot.tasks.first {
            $0.id == item.taskID
        }?.path ?? AppStrings.localized(
            "aiTaskPlan.diff.value.unavailable"
        )
        return String.localizedStringWithFormat(
            AppStrings.localized(
                "aiTaskPlan.operation.checklistTaskFormat"
            ),
            path
        )
    }

    private func categoryValue(
        id: UUID?,
        snapshot: AITaskWorkspaceSnapshot
    ) -> AITaskWorkspacePreviewValue {
        guard let id else { return .optionalText(nil) }
        let title = snapshot.categories.first { $0.id == id }?.title ??
            AppStrings.localized("aiTaskPlan.diff.value.unavailable")
        return .optionalText(title)
    }
}

private extension [AITaskWorkspaceFieldChange] {
    mutating func append(
        field: AITaskWorkspacePreviewField,
        before: AITaskWorkspacePreviewValue,
        after: AITaskWorkspacePreviewValue
    ) {
        guard before != after else { return }
        append(
            AITaskWorkspaceFieldChange(
                field: field,
                before: before,
                after: after
            )
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
            estimatedMinutes: large ? 600 : 300,
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
