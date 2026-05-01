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
        } else {
            VStack(alignment: .leading, spacing: 8) {
                if let suggestion, let task = store.task(for: suggestion.taskID) {
                    HStack(alignment: .top, spacing: 8) {
                        ChecklistItemIcon(iconName: suggestion.iconName, colorHex: suggestion.colorHex)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: AppStrings.localized("inbox.suggestion.targetFormat"), store.taskPath(for: task)))
                                .font(.caption.weight(.semibold))
                            if let reason = suggestion.reason, !reason.isEmpty {
                                Text(reason)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        store.suggestInboxItem(item)
                    } label: {
                        if store.inboxSuggestionInFlightIDs.contains(item.id) {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Label(AppStrings.localized("inbox.suggestion.suggest"), systemImage: "sparkles")
                        }
                    }
                    .disabled(store.inboxSuggestionInFlightIDs.contains(item.id))

                    Button {
                        store.presentInboxSuggestionEditor(item)
                    } label: {
                        Label(AppStrings.localized("inbox.suggestion.edit"), systemImage: "slider.horizontal.3")
                    }

                    if suggestion != nil {
                        Button {
                            store.applyInboxSuggestion(item)
                        } label: {
                            Label(AppStrings.localized("inbox.suggestion.apply"), systemImage: "arrow.turn.down.right")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .font(.caption)
                .buttonStyle(.bordered)
            }
            .padding(.leading, 74)
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
