import SwiftUI

struct QuickStartEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedIDs: [UUID]
    @State private var isDiscardConfirmationPresented = false
    let initialSelectedIDs: [UUID]
    let onSave: ([UUID]) -> Bool

    init(store: TimeTrackerStore, selectedIDs: [UUID], onSave: @escaping ([UUID]) -> Bool) {
        self.store = store
        initialSelectedIDs = selectedIDs
        self.onSave = onSave
        _selectedIDs = State(initialValue: selectedIDs)
    }

    private var availableTasks: [TaskNode] {
        let selectedIDSet = Set(selectedIDs)
        return store.tasks.filter {
            store.isTaskAvailableForTracking($0) && !selectedIDSet.contains($0.id)
        }
    }

    private var pinnedTasks: [TaskNode] {
        selectedIDs.compactMap { store.task(for: $0) }
            .filter(store.isTaskAvailableForTracking)
    }

    private func pin(_ task: TaskNode) {
        withSelectionAnimation {
            selectedIDs = OrderedTaskIDSelectionMutation.adding(
                task.id,
                to: selectedIDs
            )
        }
    }

    private func unpin(_ task: TaskNode) {
        withSelectionAnimation {
            selectedIDs = OrderedTaskIDSelectionMutation.removing(
                task.id,
                from: selectedIDs
            )
        }
    }

    private func removePinned(at offsets: IndexSet) {
        withSelectionAnimation {
            selectedIDs = OrderedTaskIDSelectionMutation.removingVisibleSelections(
                at: offsets,
                visibleIDs: pinnedTasks.map(\.id),
                from: selectedIDs
            )
        }
    }

    private func clearPinned() {
        withSelectionAnimation {
            selectedIDs.removeAll()
        }
    }

    private func movePinned(_ taskID: UUID, offset: Int) {
        guard let sourceIndex = selectedIDs.firstIndex(of: taskID) else {
            return
        }
        let destinationIndex = sourceIndex + offset
        guard selectedIDs.indices.contains(destinationIndex) else { return }
        withSelectionAnimation {
            selectedIDs.swapAt(sourceIndex, destinationIndex)
        }
    }

    private func withSelectionAnimation(_ updates: () -> Void) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.28)) {
            updates()
        }
    }

    private func cleanedPinnedIDs() -> [UUID] {
        selectedIDs.filter { id in
            guard let task = store.task(for: id) else { return false }
            return store.isTaskAvailableForTracking(task)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if pinnedTasks.isEmpty {
                        Label(AppStrings.localized("quickStart.auto"), systemImage: "clock.arrow.circlepath")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(pinnedTasks.enumerated()), id: \.element.id) { index, task in
                            HStack(spacing: 4) {
                                Button {
                                    unpin(task)
                                } label: {
                                    QuickStartEditorTaskRow(
                                        presentation: store.taskIdentityPresentation(for: task),
                                        order: index + 1,
                                        actionSystemImage: "minus.circle",
                                        actionTint: Color.primary.opacity(0.45)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(task.title)
                                .accessibilityValue(selectionValue(isPinned: true, order: index + 1))
                                .accessibilityHint(
                                    AppStrings.localized("quickStart.selection.unpinHint")
                                )
                                .accessibilityAddTraits(.isSelected)
                                .accessibilityIdentifier(
                                    "quickStart.editor.pinned.\(task.id.uuidString)"
                                )

                                QuickStartPinnedReorderControls(
                                    taskID: task.id,
                                    canMoveUp: index > 0,
                                    canMoveDown: index < pinnedTasks.count - 1,
                                    move: { offset in
                                        movePinned(task.id, offset: offset)
                                    }
                                )
                            }
                        }
                        .onDelete(perform: removePinned)
                    }

                    if !selectedIDs.isEmpty {
                        Button(role: .destructive, action: clearPinned) {
                            Label(AppStrings.localized("quickStart.clearPinned"), systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text(String(format: AppStrings.localized("quickStart.pinnedHeader"), pinnedTasks.count))
                        .accessibilityIdentifier("quickStart.editor")
                } footer: {
                    Text(.app("quickStart.pinnedFooter"))
                }

                Section(AppStrings.localized("quickStart.availableTasks")) {
                    if availableTasks.isEmpty {
                        Label(
                            AppStrings.localized("quickStart.allPinned"),
                            systemImage: "checkmark.circle"
                        )
                        .foregroundStyle(.secondary)
                        .accessibilityIdentifier("quickStart.editor.allPinned")
                    } else {
                        ForEach(availableTasks, id: \.id) { task in
                            Button {
                                pin(task)
                            } label: {
                                QuickStartEditorTaskRow(
                                    presentation: store.taskIdentityPresentation(for: task),
                                    order: nil,
                                    actionSystemImage: "plus.circle.fill",
                                    actionTint: .accentColor
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(task.title)
                            .accessibilityValue(
                                AppStrings.localized("quickStart.selection.notPinned")
                            )
                            .accessibilityHint(
                                AppStrings.localized("quickStart.selection.pinHint")
                            )
                            .accessibilityIdentifier(
                                "quickStart.editor.available.\(task.id.uuidString)"
                            )
                        }
                    }
                }
            }
            #if os(iOS)
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle(AppStrings.localized("quickStart.edit"))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(AppStrings.cancel, action: requestCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(AppStrings.localized("common.save")) {
                        if onSave(cleanedPinnedIDs()) {
                            dismiss()
                        }
                    }
                }
            }
        }
        .platformSheetFrame(width: 420, height: 520)
        .editorDiscardConfirmation(
            isPresented: $isDiscardConfirmationPresented,
            hasUnsavedChanges: selectedIDs != initialSelectedIDs,
            discard: { dismiss() }
        )
    }

    private func requestCancel() {
        if selectedIDs == initialSelectedIDs {
            dismiss()
        } else {
            isDiscardConfirmationPresented = true
        }
    }

    private func selectionValue(isPinned: Bool, order: Int?) -> String {
        guard isPinned, let order else {
            return AppStrings.localized("quickStart.selection.notPinned")
        }
        return String.localizedStringWithFormat(
            AppStrings.localized("quickStart.selection.pinnedOrder"),
            order
        )
    }
}

private struct QuickStartPinnedReorderControls: View {
    let taskID: UUID
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void

    var body: some View {
        HStack(spacing: 0) {
            Button {
                move(-1)
            } label: {
                Image(systemName: "chevron.up")
                    .frame(
                        width: AppLayout.minimumInteractiveTarget,
                        height: AppLayout.minimumInteractiveTarget
                    )
            }
            .disabled(canMoveUp == false)
            .accessibilityLabel(AppStrings.localized("common.moveUp"))
            .accessibilityIdentifier(
                "quickStart.editor.moveUp.\(taskID.uuidString)"
            )

            Button {
                move(1)
            } label: {
                Image(systemName: "chevron.down")
                    .frame(
                        width: AppLayout.minimumInteractiveTarget,
                        height: AppLayout.minimumInteractiveTarget
                    )
            }
            .disabled(canMoveDown == false)
            .accessibilityLabel(AppStrings.localized("common.moveDown"))
            .accessibilityIdentifier(
                "quickStart.editor.moveDown.\(taskID.uuidString)"
            )
        }
        .buttonStyle(.borderless)
    }
}

private struct QuickStartEditorTaskRow: View {
    let presentation: TaskIdentityPresentation
    let order: Int?
    let actionSystemImage: String
    let actionTint: Color

    var body: some View {
        HStack(spacing: 12) {
            TaskIdentityRow(presentation: presentation)
                .layoutPriority(1)
            if let order {
                Text("#\(order)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .fixedSize()
            }
            Image(systemName: actionSystemImage)
                .foregroundStyle(actionTint)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
