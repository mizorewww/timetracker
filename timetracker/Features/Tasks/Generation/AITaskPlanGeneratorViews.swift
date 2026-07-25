import MarkdownView
import SwiftUI

enum AITaskPlanCreationFeedback: Equatable {
    case created
    case failed(message: String)
}

struct AITaskPlanGeneratorSheet: View {
    private enum PendingDiscardAction {
        case dismissSheet
        case returnToRequest
    }

    let store: TimeTrackerStore
    let onConfigureAI: () -> Void
    let onCreate: (AITaskPlanDraft) -> AITaskPlanCreationFeedback

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var requestText = ""
    @State private var generatedDraft: AITaskPlanDraft?
    @State private var generationTask: Task<Void, Never>?
    @State private var generationRequestID = UUID()
    @State private var isGenerating = false
    @State private var generationProgress: LLMGenerationProgress?
    @State private var isCreating = false
    @State private var errorMessage: String?
    @State private var pendingDiscardAction: PendingDiscardAction?
    @State private var isDiscardConfirmationPresented = false

    private var usesUITestFixture: Bool {
        #if DEBUG
        CommandLine.arguments.contains("--uitesting-ai-task-plan")
            || CommandLine.arguments.contains("--uitesting-ai-task-plan-large")
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
                LLMModelService.modelsURL(endpoint: store.preferences.llmEndpoint) != nil &&
                    !store.preferences.llmAPIKey
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty &&
                    store.preferences.llmAvailableModelIDs
                    .contains(store.preferences.llmSelectedModel)
            )
    }

    private var hasUnsavedChanges: Bool {
        !requestText.isEmpty || generatedDraft != nil
    }

    var body: some View {
        NavigationStack {
            Group {
                if generatedDraft != nil {
                    preview
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
                            .disabled(isCreating)
                            .accessibilityIdentifier("aiTaskPlan.cancel")
                    }

                    if let generatedDraft {
                        ToolbarItem(placement: .confirmationAction) {
                            Button {
                                create(generatedDraft)
                            } label: {
                                if isCreating {
                                    ProgressView()
                                        .controlSize(.small)
                                } else {
                                    Text(.app("aiTaskPlan.create"))
                                }
                            }
                            .disabled(
                                isCreating ||
                                    generatedDraft.taskCount == 0 ||
                                    generatedDraft.firstValidationMessage != nil
                            )
                            .accessibilityIdentifier("aiTaskPlan.create")
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
                                    .trimmingCharacters(in: .whitespacesAndNewlines)
                                    .isEmpty
                            )
                            .accessibilityIdentifier("aiTaskPlan.generate")
                        }
                    }
                }
        }
        .platformSheetFrame(width: 680, height: 720)
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: hasUnsavedChanges || isCreating,
            discard: performPendingDiscard
        )
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

                if isGenerating {
                    Section {
                        HStack(spacing: 12) {
                            ProgressView()
                                .controlSize(.small)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(.app("aiTaskPlan.generating"))
                                if let generationProgress {
                                    Text(
                                        String.localizedStringWithFormat(
                                            AppStrings.localized("aiTaskPlan.generating.tokens"),
                                            Int64(generationProgress.displayedOutputTokens)
                                        )
                                    )
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                }
                            }
                            Spacer(minLength: 8)
                            Button(
                                AppStrings.localized("aiTaskPlan.stopGenerating"),
                                action: stopGenerating
                            )
                        }
                        .frame(minHeight: AppLayout.minimumInteractiveTarget)
                        .accessibilityIdentifier("aiTaskPlan.generating")
                    }
                }

                inlineErrorSection
            } else {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(.app("aiTaskPlan.configurationRequired.title"))
                                .font(.headline)
                            Text(.app("aiTaskPlan.configurationRequired.message"))
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
                            AppStrings.localized("aiTaskPlan.configureAI"),
                            systemImage: "slider.horizontal.3"
                        )
                    }
                    .accessibilityIdentifier("aiTaskPlan.configureAI")
                }
            }
        }
        .formStyle(.grouped)
    }

    private var preview: some View {
        List {
            if let generatedDraft {
                Section {
                    Label {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(.app("aiTaskPlan.preview.notice"))
                                .font(.headline)
                            Text(generatedDraft.localizedSummary)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.purple)
                    }

                    Button {
                        requestReturnToRequest()
                    } label: {
                        Label(
                            AppStrings.localized("aiTaskPlan.editRequest"),
                            systemImage: "arrow.backward"
                        )
                    }
                    .disabled(isCreating)
                    .accessibilityIdentifier("aiTaskPlan.editRequest")
                } footer: {
                    Text(.app("aiTaskPlan.preview.footer"))
                }

                AITaskPlanDraftPreview(draft: generatedDraftBinding)

                if generatedDraft.reasoningContent != nil ||
                    generatedDraft.rawResponseContent != nil
                {
                    Section {
                        if let reasoning = generatedDraft.reasoningContent {
                            DisclosureGroup {
                                ScrollView {
                                    MarkdownView(reasoning)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 320)
                                .padding(.vertical, 4)
                            } label: {
                                Label(
                                    AppStrings.localized("aiTaskPlan.reasoning.title"),
                                    systemImage: "brain"
                                )
                            }
                            .accessibilityIdentifier("aiTaskPlan.reasoning")
                        }

                        if let rawOutput = generatedDraft.rawResponseContent {
                            DisclosureGroup {
                                ScrollView {
                                    Text(rawOutput)
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                        .textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .frame(maxHeight: 320)
                                .padding(.vertical, 4)
                            } label: {
                                Label(
                                    AppStrings.localized("aiTaskPlan.rawOutput.title"),
                                    systemImage: "curlybraces"
                                )
                            }
                            .accessibilityIdentifier("aiTaskPlan.rawOutput")
                        }
                    }
                }

                if generatedDraft.taskCount == 0 {
                    Section {
                        ContentUnavailableView(
                            AppStrings.localized("aiTaskPlan.emptyDraft.title"),
                            systemImage: "checklist",
                            description: Text(.app("aiTaskPlan.emptyDraft.message"))
                        )
                    }
                } else if let validationMessage = generatedDraft.firstValidationMessage {
                    Section {
                        Label(validationMessage, systemImage: "exclamationmark.circle.fill")
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("aiTaskPlan.validationError")
                    }
                }
            }

            inlineErrorSection
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
    }

    @ViewBuilder
    private var inlineErrorSection: some View {
        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.subheadline)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .accessibilityIdentifier("aiTaskPlan.error")

                if generatedDraft == nil, isConfigured, !isGenerating {
                    Button(
                        AppStrings.localized("aiTaskPlan.retry"),
                        action: generate
                    )
                    .disabled(
                        requestText
                            .trimmingCharacters(in: .whitespacesAndNewlines)
                            .isEmpty
                    )
                    .accessibilityIdentifier("aiTaskPlan.retry")
                }
            }
        }
    }

    private var generatedDraftBinding: Binding<AITaskPlanDraft> {
        Binding {
            generatedDraft ?? AITaskPlanDraft(
                categories: [],
                tasks: [],
                modelID: ""
            )
        } set: {
            generatedDraft = $0
        }
    }

    private func generate() {
        generationTask?.cancel()
        let request = requestText
        let instructions = store.preferences.llmTaskPlanInstructions
        let endpoint = store.preferences.llmEndpoint
        let apiKey = store.preferences.llmAPIKey
        let modelID = store.preferences.llmSelectedModel
        let requestID = UUID()
        generationRequestID = requestID
        errorMessage = nil
        generationProgress = nil
        isGenerating = true

        generationTask = Task { @MainActor in
            do {
                let draft: AITaskPlanDraft
                if usesLargeUITestFixture {
                    try await Task.sleep(for: .milliseconds(180))
                    draft = .largeUITestFixture
                } else if usesUITestFixture {
                    try await Task.sleep(for: .milliseconds(180))
                    draft = .uiTestFixture
                } else {
                    draft = try await LLMTaskPlanService().generateStreaming(
                        request: request,
                        instructions: instructions,
                        endpoint: endpoint,
                        apiKey: apiKey,
                        modelID: modelID
                    ) { progress in
                        Task { @MainActor in
                            guard generationRequestID == requestID,
                                  !Task.isCancelled
                            else { return }
                            generationProgress = progress
                        }
                    }
                }
                guard !Task.isCancelled, generationRequestID == requestID else {
                    return
                }
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    generatedDraft = draft
                }
            } catch is CancellationError {
                // Cancellation is an explicit user action, not an error state.
            } catch {
                guard !Task.isCancelled, generationRequestID == requestID else {
                    return
                }
                errorMessage = error.localizedDescription
            }
            if generationRequestID == requestID {
                isGenerating = false
                generationTask = nil
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

    private func returnToRequest() {
        errorMessage = nil
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            generatedDraft = nil
        }
    }

    private func create(_ draft: AITaskPlanDraft) {
        guard !isCreating else { return }
        isCreating = true
        errorMessage = nil
        let creationDraft = draft.pruningUnusedCategories()
        switch onCreate(creationDraft) {
        case .created:
            dismiss()
        case let .failed(message):
            errorMessage = message
            isCreating = false
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
            returnToRequest()
        case nil:
            break
        }
    }
}

private struct AITaskPlanDraftPreview: View {
    @Binding var draft: AITaskPlanDraft

    var body: some View {
        ForEach(draft.previewSections) { section in
            Section {
                ForEach(section.rows) { row in
                    if let task = draft.tasks.first(where: { $0.id == row.taskID }) {
                        AITaskPlanTaskDraftRow(
                            task: taskBinding(for: task),
                            depth: row.depth,
                            removeTask: {
                                draft.removeTaskSubtree(rootID: row.taskID)
                            }
                        )
                    }
                }
            } header: {
                AITaskPlanCategoryDraftHeader(
                    draft: $draft,
                    categoryID: section.categoryID
                )
            }
        }
    }

    private func taskBinding(
        for fallback: AITaskPlanTaskDraft
    ) -> Binding<AITaskPlanTaskDraft> {
        Binding {
            draft.tasks.first(where: { $0.id == fallback.id }) ?? fallback
        } set: { updatedTask in
            guard let index = draft.tasks.firstIndex(where: {
                $0.id == fallback.id
            }) else {
                return
            }
            draft.tasks[index] = updatedTask
        }
    }
}

private struct AITaskPlanCategoryDraftHeader: View {
    @Binding var draft: AITaskPlanDraft
    let categoryID: UUID?

    var body: some View {
        if let categoryID,
           let category = draft.categories.first(where: {
               $0.id == categoryID
           })
        {
            HStack(spacing: 8) {
                TaskIcon(
                    visual: TaskVisualPresentation(
                        iconName: category.iconName,
                        colorHex: category.colorHex
                    ),
                    size: 30
                )

                TextField(
                    AppStrings.localized("aiTaskPlan.categoryName"),
                    text: categoryTitleBinding(
                        categoryID: categoryID,
                        fallback: category.title
                    ),
                    axis: .vertical
                )
                .font(.subheadline.weight(.semibold))
                .lineLimit(1 ... 2)
                .textFieldStyle(.plain)
                .accessibilityLabel(AppStrings.localized("aiTaskPlan.categoryName"))

                Spacer(minLength: 8)

                Menu {
                    Button(role: .destructive) {
                        draft.removeCategory(categoryID)
                    } label: {
                        Label(
                            AppStrings.localized("aiTaskPlan.removeCategory"),
                            systemImage: "trash"
                        )
                    }
                } label: {
                    TrailingMenuLabel(systemImage: "ellipsis.circle")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(
                    AppStrings.localized("aiTaskPlan.categoryActions")
                )
            }
            .textCase(nil)
        } else {
            Label(
                AppStrings.localized("aiTaskPlan.uncategorized"),
                systemImage: "tray"
            )
            .font(.subheadline.weight(.semibold))
            .textCase(nil)
        }
    }

    private func categoryTitleBinding(
        categoryID: UUID,
        fallback: String
    ) -> Binding<String> {
        Binding {
            draft.categories.first(where: { $0.id == categoryID })?.title ?? fallback
        } set: { title in
            guard let index = draft.categories.firstIndex(where: {
                $0.id == categoryID
            }) else {
                return
            }
            draft.categories[index].title = title
        }
    }
}

private struct AITaskPlanTaskDraftRow: View {
    @Binding var task: AITaskPlanTaskDraft
    let depth: Int
    let removeTask: () -> Void

    var body: some View {
        // Each child of this Group is its own List row, matching the task
        // detail editor: the task header row, then quantity/recurrence
        // toggles as independent rows, then checklist rows.
        headerRow

        AITaskPlanTaskProgressDraftEditor(task: $task)
            .padding(.leading, nestedContentLeadingInset)

        ForEach(task.checklistItems) { item in
            AITaskPlanChecklistDraftRow(
                item: checklistItemBinding(for: item),
                remove: {
                    task.checklistItems.removeAll {
                        $0.id == item.id
                    }
                }
            )
            .padding(.leading, nestedContentLeadingInset)
        }
    }

    private var depthLeadingInset: CGFloat {
        CGFloat(min(depth, LLMTaskPlanService.maximumTaskDepth)) * 12
    }

    private var nestedContentLeadingInset: CGFloat {
        depthLeadingInset + 44
    }

    private var headerRow: some View {
        HStack(alignment: .top, spacing: 10) {
            TaskIcon(
                visual: TaskVisualPresentation(
                    iconName: task.iconName,
                    colorHex: task.colorHex
                ),
                size: 34
            )

            VStack(alignment: .leading, spacing: 4) {
                TextField(
                    AppStrings.localized("aiTaskPlan.taskName"),
                    text: $task.title,
                    axis: .vertical
                )
                .font(.body.weight(.semibold))
                .lineLimit(1 ... 3)
                .textFieldStyle(.plain)
                .accessibilityLabel(AppStrings.localized("aiTaskPlan.taskName"))
                .accessibilityIdentifier(
                    "aiTaskPlan.task.\(task.id.uuidString)"
                )

                if !task.notes.isEmpty {
                    Text(task.notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let estimatedMinutes = task.estimatedMinutes {
                    Label(
                        DurationFormatter.compact(estimatedMinutes * 60),
                        systemImage: "clock"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 4)

            Menu {
                Button(role: .destructive, action: removeTask) {
                    Label(
                        AppStrings.localized("aiTaskPlan.removeTask"),
                        systemImage: "trash"
                    )
                }
            } label: {
                TrailingMenuLabel(systemImage: "ellipsis.circle")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(AppStrings.localized("aiTaskPlan.taskActions"))
        }
        .padding(.leading, depthLeadingInset)
        .frame(minHeight: AppLayout.minimumInteractiveTarget)
    }

    private func checklistItemBinding(
        for fallback: AITaskPlanChecklistDraft
    ) -> Binding<AITaskPlanChecklistDraft> {
        Binding {
            task.checklistItems.first(where: { $0.id == fallback.id }) ?? fallback
        } set: { updatedItem in
            guard let index = task.checklistItems.firstIndex(where: {
                $0.id == fallback.id
            }) else {
                return
            }
            task.checklistItems[index] = updatedItem
        }
    }
}

private struct AITaskPlanTaskProgressDraftEditor: View {
    @Binding var task: AITaskPlanTaskDraft

    private var accessibilityIdentifierPrefix: String {
        "aiTaskPlan.task.\(task.id.uuidString)"
    }

    var body: some View {
        // Independent List rows, like the task detail quantity and
        // recurrence sections, so the system provides row height, insets,
        // and separators instead of cramped in-row stacking.
        Toggle(
            AppStrings.localized("task.quantity.editor.toggle"),
            isOn: quantityEnabledBinding
        )
        .accessibilityIdentifier(
            "\(accessibilityIdentifierPrefix).quantity.toggle"
        )

        if task.quantityGoal != nil {
            quantityTargetEditor
            quantityUnitEditor
        }

        Toggle(
            AppStrings.localized("task.recurrence.editor.daily"),
            isOn: dailyRecurrenceEnabledBinding
        )
        .accessibilityIdentifier(
            "\(accessibilityIdentifierPrefix).recurrence.daily"
        )
    }

    private var quantityTargetEditor: some View {
        LabeledContent {
            TextField(
                AppStrings.localized("task.quantity.editor.target"),
                value: quantityTargetBinding,
                format: .number.grouping(.never)
            )
            .multilineTextAlignment(.trailing)
            #if os(iOS)
                .keyboardType(.numberPad)
            #endif
                .accessibilityIdentifier(
                    "\(accessibilityIdentifierPrefix).quantity.target"
                )
        } label: {
            Text(.app("task.quantity.editor.target"))
        }
    }

    private var quantityUnitEditor: some View {
        LabeledContent {
            TextField(
                AppStrings.localized("task.quantity.editor.unit"),
                text: quantityUnitBinding
            )
            .multilineTextAlignment(.trailing)
            .submitLabel(.done)
            .accessibilityIdentifier(
                "\(accessibilityIdentifierPrefix).quantity.unit"
            )
        } label: {
            Text(.app("task.quantity.editor.unit"))
        }
    }

    private var quantityEnabledBinding: Binding<Bool> {
        Binding {
            task.quantityGoal != nil
        } set: { isEnabled in
            var updated = task
            if isEnabled {
                guard updated.quantityGoal == nil else { return }
                updated.quantityGoal = TaskQuantityGoalDraft()
            } else {
                updated.quantityGoal = nil
            }
            task = updated
        }
    }

    private var quantityTargetBinding: Binding<Int> {
        Binding {
            task.quantityGoal?.targetAmount ?? 1
        } set: { targetAmount in
            guard var quantityGoal = task.quantityGoal else { return }
            quantityGoal.targetAmount = targetAmount
            var updated = task
            updated.quantityGoal = quantityGoal
            task = updated
        }
    }

    private var quantityUnitBinding: Binding<String> {
        Binding {
            task.quantityGoal?.unitLabel ?? ""
        } set: { unitLabel in
            guard var quantityGoal = task.quantityGoal else { return }
            quantityGoal.unitLabel = unitLabel
            var updated = task
            updated.quantityGoal = quantityGoal
            task = updated
        }
    }

    private var dailyRecurrenceEnabledBinding: Binding<Bool> {
        Binding {
            task.dailyRecurrence?.isEnabled == true
        } set: { isEnabled in
            var updated = task
            if var recurrence = updated.dailyRecurrence {
                recurrence.isEnabled = true
                updated.dailyRecurrence = isEnabled ? recurrence : nil
            } else if isEnabled {
                updated.dailyRecurrence = TaskDailyRecurrenceDraft()
            }
            task = updated
        }
    }
}

private struct AITaskPlanChecklistDraftRow: View {
    @Binding var item: AITaskPlanChecklistDraft
    let remove: () -> Void
    @FocusState private var isTitleFocused: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            ChecklistItemIcon(
                iconName: item.iconName,
                colorHex: item.colorHex
            )

            TextField(
                AppStrings.localized("aiTaskPlan.checklistName"),
                text: $item.title,
                axis: .vertical
            )
            .font(.subheadline)
            .lineLimit(1 ... 3)
            .textFieldStyle(.plain)
            .focused($isTitleFocused)
            .frame(
                minHeight: AppLayout.minimumInteractiveTarget,
                alignment: .leading
            )
            .contentShape([.interaction, .accessibility], Rectangle())
            .onTapGesture {
                isTitleFocused = true
            }
            .accessibilityLabel(AppStrings.localized("aiTaskPlan.checklistName"))

            Button(role: .destructive, action: remove) {
                Image(systemName: "minus.circle")
                    .frame(
                        minWidth: AppLayout.minimumInteractiveTarget,
                        minHeight: AppLayout.minimumInteractiveTarget
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("aiTaskPlan.removeChecklist"))
        }
    }
}

private struct AITaskPlanPreviewSection: Identifiable {
    let id: String
    let categoryID: UUID?
    let rows: [AITaskPlanPreviewRow]
}

private struct AITaskPlanPreviewRow: Identifiable {
    let taskID: UUID
    let depth: Int

    var id: UUID {
        taskID
    }
}

private extension AITaskPlanDraft {
    var taskCount: Int {
        tasks.count
    }

    var checklistItemCount: Int {
        tasks.reduce(0) { $0 + $1.checklistItems.count }
    }

    var usedCategoryIDs: Set<UUID> {
        Set(
            tasks.compactMap { task in
                guard task.parentID == nil else { return nil }
                return task.categoryID
            }
        )
    }

    var localizedSummary: String {
        String.localizedStringWithFormat(
            AppStrings.localized("aiTaskPlan.summaryFormat"),
            Int64(usedCategoryIDs.count),
            Int64(taskCount),
            Int64(checklistItemCount)
        )
    }

    var firstValidationMessage: String? {
        for category in categories where usedCategoryIDs.contains(category.id) {
            do {
                _ = try TaskPersistencePolicy.prepareCategory(
                    title: category.title,
                    colorHex: category.colorHex,
                    iconName: category.iconName
                )
            } catch {
                return error.localizedDescription
            }
        }

        for task in tasks {
            do {
                _ = try TaskPersistencePolicy.prepareTask(
                    title: task.title,
                    colorHex: task.colorHex,
                    iconName: task.iconName,
                    notes: task.notes
                )
                _ = try ChecklistDraftPersistencePolicy.prepare(
                    task.checklistItems.map {
                        ChecklistEditorDraft(
                            title: $0.title,
                            iconName: $0.iconName,
                            colorHex: $0.colorHex
                        )
                    }
                )
                _ = try TaskProgressDraftPersistencePolicy.prepare(
                    quantityGoal: task.quantityGoal,
                    dailyRecurrence: task.dailyRecurrence
                )
            } catch {
                return error.localizedDescription
            }
        }
        return nil
    }

    var previewSections: [AITaskPlanPreviewSection] {
        var result: [AITaskPlanPreviewSection] = []
        for category in categories {
            let rows = previewRows(categoryID: category.id)
            if !rows.isEmpty {
                result.append(
                    AITaskPlanPreviewSection(
                        id: category.id.uuidString,
                        categoryID: category.id,
                        rows: rows
                    )
                )
            }
        }

        let uncategorizedRows = previewRows(categoryID: nil)
        if !uncategorizedRows.isEmpty {
            result.append(
                AITaskPlanPreviewSection(
                    id: "uncategorized",
                    categoryID: nil,
                    rows: uncategorizedRows
                )
            )
        }
        return result
    }

    func previewRows(categoryID: UUID?) -> [AITaskPlanPreviewRow] {
        let taskByID = Dictionary(uniqueKeysWithValues: tasks.map { ($0.id, $0) })
        let childIDsByParentID = Dictionary(grouping: tasks, by: \.parentID)
            .mapValues { $0.map(\.id) }
        let roots = tasks.filter {
            $0.parentID == nil && $0.categoryID == categoryID
        }
        var result: [AITaskPlanPreviewRow] = []
        var visited = Set<UUID>()

        func append(_ taskID: UUID, depth: Int) {
            guard taskByID[taskID] != nil, visited.insert(taskID).inserted else {
                return
            }
            result.append(AITaskPlanPreviewRow(taskID: taskID, depth: depth))
            for childID in childIDsByParentID[taskID] ?? [] {
                append(childID, depth: depth + 1)
            }
        }

        for root in roots {
            append(root.id, depth: 0)
        }
        return result
    }

    mutating func removeTaskSubtree(rootID: UUID) {
        let childIDsByParentID = Dictionary(grouping: tasks, by: \.parentID)
            .mapValues { $0.map(\.id) }
        var removedIDs = Set<UUID>()
        var pending = [rootID]
        while let next = pending.popLast(), removedIDs.insert(next).inserted {
            pending.append(contentsOf: childIDsByParentID[next] ?? [])
        }
        tasks.removeAll { removedIDs.contains($0.id) }
    }

    mutating func removeCategory(_ categoryID: UUID) {
        for index in tasks.indices
            where tasks[index].parentID == nil && tasks[index].categoryID == categoryID
        {
            tasks[index].categoryID = nil
        }
        categories.removeAll { $0.id == categoryID }
    }

    func pruningUnusedCategories() -> AITaskPlanDraft {
        var copy = self
        let usedIDs = copy.usedCategoryIDs
        copy.categories.removeAll { !usedIDs.contains($0.id) }
        return copy
    }

    /// One task carrying 150 checklist items, used to verify that large
    /// generated plans render and create faithfully.
    static var largeUITestFixture: AITaskPlanDraft {
        let categoryID = UUID(
            uuidString: "20000000-0000-4000-8000-000000000010"
        )!
        let taskID = UUID(
            uuidString: "20000000-0000-4000-8000-000000000110"
        )!
        return AITaskPlanDraft(
            categories: [
                AITaskPlanCategoryDraft(
                    id: categoryID,
                    title: "Reading",
                    iconName: "book",
                    colorHex: "5E5CE6"
                ),
            ],
            tasks: [
                AITaskPlanTaskDraft(
                    id: taskID,
                    categoryID: categoryID,
                    title: "Read 150 Chapters",
                    notes: "A faithful large plan.",
                    iconName: "book",
                    colorHex: "5E5CE6",
                    checklistItems: (1 ... 150).map { index in
                        AITaskPlanChecklistDraft(
                            title: "Chapter \(index)",
                            iconName: "book",
                            colorHex: "5E5CE6"
                        )
                    }
                ),
            ],
            modelID: "uitest-large-fixture"
        )
    }

    static var uiTestFixture: AITaskPlanDraft {
        let wellnessID = UUID(
            uuidString: "20000000-0000-4000-8000-000000000001"
        )!
        let readingCategoryID = UUID(
            uuidString: "20000000-0000-4000-8000-000000000002"
        )!
        let pushupsID = UUID(
            uuidString: "20000000-0000-4000-8000-000000000101"
        )!
        let techniqueID = UUID(
            uuidString: "20000000-0000-4000-8000-000000000102"
        )!
        let readingID = UUID(
            uuidString: "20000000-0000-4000-8000-000000000103"
        )!
        return AITaskPlanDraft(
            categories: [
                AITaskPlanCategoryDraft(
                    id: wellnessID,
                    title: "Fitness",
                    iconName: "dumbbell",
                    colorHex: "34C759"
                ),
                AITaskPlanCategoryDraft(
                    id: readingCategoryID,
                    title: "Reading",
                    iconName: "book",
                    colorHex: "5E5CE6"
                ),
            ],
            tasks: [
                AITaskPlanTaskDraft(
                    id: pushupsID,
                    categoryID: wellnessID,
                    title: "Daily 50 Push-Ups",
                    notes: "Build a repeatable routine with safe form.",
                    estimatedMinutes: 10,
                    iconName: "dumbbell",
                    colorHex: "34C759",
                    quantityGoal: TaskQuantityGoalDraft(
                        targetAmount: 50,
                        unitLabel: "push-ups"
                    ),
                    dailyRecurrence: TaskDailyRecurrenceDraft(
                        isEnabled: true,
                        startDayKey: "2026-07-22",
                        timeZoneIdentifier: "Asia/Singapore"
                    ),
                    checklistItems: [
                        AITaskPlanChecklistDraft(
                            title: "Warm up shoulders",
                            iconName: "figure.walk",
                            colorHex: "34C759"
                        ),
                        AITaskPlanChecklistDraft(
                            title: "Complete 5 sets of 10",
                            iconName: "checkmark.circle",
                            colorHex: "34C759"
                        ),
                    ]
                ),
                AITaskPlanTaskDraft(
                    id: techniqueID,
                    parentID: pushupsID,
                    title: "Review Push-Up Technique",
                    estimatedMinutes: 15,
                    iconName: "target",
                    colorHex: "00C7BE",
                    checklistItems: [
                        AITaskPlanChecklistDraft(
                            title: "Check wrist and elbow alignment",
                            iconName: "target",
                            colorHex: "00C7BE"
                        ),
                    ]
                ),
                AITaskPlanTaskDraft(
                    id: readingID,
                    categoryID: readingCategoryID,
                    title: "Read 10 Chapters",
                    estimatedMinutes: 300,
                    iconName: "book",
                    colorHex: "5E5CE6",
                    checklistItems: (1 ... 10).map { chapter in
                        AITaskPlanChecklistDraft(
                            title: "Chapter \(chapter)",
                            iconName: "pencil.and.list.clipboard",
                            colorHex: "5E5CE6"
                        )
                    }
                ),
            ],
            modelID: "ui-test",
            reasoningContent: """
            The user wants a reading and fitness plan. I will create two \
            categories, put the push-up routine under Fitness with a daily \
            recurrence, and place the reading task under Reading with one \
            checklist item per chapter.
            """,
            rawResponseContent: #"{"categories":[],"tasks":[{"reference":"root","title":"Read 10 Chapters"}],"checklistItems":[]}"#
        )
    }
}
