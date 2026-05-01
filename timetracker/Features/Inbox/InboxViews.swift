import SwiftUI

struct InboxView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draftTitle = ""
    @State private var addFocusToken = 0

    private var items: [InboxItem] {
        store.inboxItemsForDisplay
    }

    var body: some View {
        List {
            Section {
                InlineChecklistAddRow(
                    title: $draftTitle,
                    placeholder: AppStrings.localized("inbox.addPlaceholder"),
                    focusToken: addFocusToken,
                    submit: submitDraft
                )

                if items.isEmpty {
                    EmptyStateRow(
                        title: AppStrings.localized("inbox.empty"),
                        icon: "tray"
                    )
                } else {
                    ForEach(items) { item in
                        InboxItemRow(store: store, item: item)
                    }
                }
            } header: {
                Text(AppStrings.inbox)
            } footer: {
                Text(.app("inbox.footer"))
            }
        }
        .navigationTitle(AppStrings.inbox)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .toolbar {
            Button {
                addFocusToken += 1
            } label: {
                Label(AppStrings.localized("inbox.add"), systemImage: "plus")
            }
        }
    }

    private func submitDraft() {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            addFocusToken += 1
            return
        }
        store.addInboxItem(title: title)
        draftTitle = ""
        addFocusToken += 1
    }
}

private struct InboxItemRow: View {
    @ObservedObject var store: TimeTrackerStore
    let item: InboxItem
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EditableChecklistTextRow(
                title: $draftTitle,
                isCompleted: item.isCompleted,
                iconName: suggestion?.iconName ?? ChecklistVisualSanitizer.defaultIcon,
                colorHex: suggestion?.colorHex ?? ChecklistVisualSanitizer.defaultColor,
                placeholder: AppStrings.localized("inbox.itemPlaceholder"),
                toggle: {
                    withAnimation(.snappy(duration: 0.22)) {
                        store.toggleInboxItem(item)
                    }
                },
                commit: commitTitleIfNeeded
            )
            suggestionControls
        }
        .onAppear {
            draftTitle = item.title
        }
        .onChange(of: item.title) { _, newValue in
            draftTitle = newValue
        }
        .swipeActions {
            Button(role: .destructive) {
                store.deleteInboxItem(item)
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        }
        .contextMenu {
            Button {
                store.toggleInboxItem(item)
            } label: {
                Label(
                    item.isCompleted ? AppStrings.localized("inbox.markOpen") : AppStrings.localized("inbox.markCompleted"),
                    systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                )
            }
            Button(role: .destructive) {
                store.deleteInboxItem(item)
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        }
    }

    @ViewBuilder
    private var suggestionControls: some View {
        if item.isCompleted {
            EmptyView()
        } else if store.inboxSuggestionInFlightIDs.contains(item.id) {
            Label(AppStrings.localized("inbox.suggestion.generating"), systemImage: "sparkles")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            if let suggestion, let task = store.task(for: suggestion.taskID) {
                HStack(spacing: 8) {
                    Image(systemName: ChecklistVisualSanitizer.sanitizedIcon(suggestion.iconName))
                        .foregroundStyle(Color(hex: ChecklistVisualSanitizer.sanitizedColor(suggestion.colorHex)) ?? .secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(String(format: AppStrings.localized("inbox.suggestion.targetFormat"), store.taskPath(for: task)))
                            .lineLimit(1)
                            .foregroundStyle(.secondary)
                    }
                    .font(.caption.weight(.semibold))

                    Spacer(minLength: 0)

                    Button(role: .destructive) {
                        store.discardInboxSuggestion(item)
                    } label: {
                        Label(AppStrings.localized("inbox.suggestion.discard"), systemImage: "xmark")
                    }
                    .labelStyle(.iconOnly)

                    Button {
                        store.applyInboxSuggestion(item)
                    } label: {
                        Label(AppStrings.localized("inbox.suggestion.apply"), systemImage: "arrow.turn.down.right")
                    }
                    .buttonStyle(.borderedProminent)
                }
                .font(.caption)
                .controlSize(.small)
            }
        }
    }

    private var suggestion: InboxSuggestion? {
        store.inboxSuggestion(for: item)
    }

    private func commitTitleIfNeeded() {
        let normalizedDraft = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDraft != item.title else { return }
        store.updateInboxItemTitle(item, title: normalizedDraft)
    }
}
