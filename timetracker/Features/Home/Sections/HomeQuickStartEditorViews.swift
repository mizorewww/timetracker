import Foundation
import SwiftUI

struct QuickStartEditorSheet: View {
    let store: TimeTrackerStore
    @Environment(\.dismiss) private var dismiss
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
        store.tasks.filter(store.isTaskAvailableForTracking)
    }

    private var pinnedTasks: [TaskNode] {
        selectedIDs.compactMap { store.task(for: $0) }
            .filter(store.isTaskAvailableForTracking)
    }

    private func isPinned(_ task: TaskNode) -> Bool {
        selectedIDs.contains(task.id)
    }

    private func togglePinned(_ task: TaskNode) {
        if let index = selectedIDs.firstIndex(of: task.id) {
            selectedIDs.remove(at: index)
        } else {
            selectedIDs.append(task.id)
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
                            QuickStartPinnedTaskRow(
                                presentation: store.taskIdentityPresentation(for: task),
                                order: index + 1
                            )
                        }
                        .onDelete { offsets in
                            selectedIDs.remove(atOffsets: offsets)
                        }
                    }

                    if !selectedIDs.isEmpty {
                        Button(role: .destructive) {
                            selectedIDs.removeAll()
                        } label: {
                            Label(AppStrings.localized("quickStart.clearPinned"), systemImage: "xmark.circle")
                        }
                    }
                } header: {
                    Text(String(format: AppStrings.localized("quickStart.pinnedHeader"), pinnedTasks.count))
                } footer: {
                    Text(.app("quickStart.pinnedFooter"))
                }

                Section(AppStrings.localized("quickStart.allTasks")) {
                    ForEach(availableTasks, id: \.id) { task in
                        let pinned = isPinned(task)
                        Button {
                            togglePinned(task)
                        } label: {
                            QuickStartSelectableTaskRow(
                                presentation: store.taskIdentityPresentation(for: task),
                                isPinned: pinned,
                                order: selectedIDs.firstIndex(of: task.id).map { $0 + 1 },
                                isDisabled: false
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(task.title)
                        .accessibilityValue(selectionValue(isPinned: pinned, order: selectedIDs.firstIndex(of: task.id).map { $0 + 1 }))
                        .accessibilityHint(
                            AppStrings.localized(
                                pinned
                                    ? "quickStart.selection.unpinHint"
                                    : "quickStart.selection.pinHint"
                            )
                        )
                        .accessibilityAddTraits(pinned ? .isSelected : [])
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

private struct QuickStartPinnedTaskRow: View {
    let presentation: TaskIdentityPresentation
    let order: Int

    var body: some View {
        let text = presentation.text(for: .standard)
        HStack(spacing: 12) {
            TaskIcon(visual: presentation.visual, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.primary)
                    .foregroundStyle(.primary)
                if let secondary = text.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("#\(order)")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}

private struct QuickStartSelectableTaskRow: View {
    let presentation: TaskIdentityPresentation
    let isPinned: Bool
    let order: Int?
    let isDisabled: Bool

    var body: some View {
        let text = presentation.text(for: .standard)
        HStack(spacing: 12) {
            TaskIcon(visual: presentation.visual, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(text.primary)
                    .foregroundStyle(isDisabled ? .secondary : .primary)
                if let secondary = text.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            if let order {
                Text("#\(order)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Image(systemName: isPinned ? "checkmark.circle.fill" : "plus.circle")
                .foregroundStyle(isPinned ? .blue : .secondary)
                .accessibilityHidden(true)
        }
        .contentShape(Rectangle())
        .opacity(isDisabled ? 0.55 : 1)
        .accessibilityElement(children: .combine)
    }
}
