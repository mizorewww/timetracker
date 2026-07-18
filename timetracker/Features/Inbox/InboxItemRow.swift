import SwiftUI

struct InboxItemRow: View {
    let store: TimeTrackerStore
    let item: InboxItem
    let isCompact: Bool
    let requestDelete: () -> Void
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .top, spacing: 4) {
                EditableChecklistTextRow(
                    title: $draftTitle,
                    isCompleted: item.isCompleted,
                    placeholder: AppStrings.localized("inbox.itemPlaceholder"),
                    showsIcon: false,
                    completionVisualSize: 24,
                    textStyle: .body,
                    toggle: {
                        store.toggleInboxItem(item)
                    },
                    commit: commitTitleIfNeeded
                )

                itemMenu
            }

            suggestionBar
        }
        .onAppear {
            draftTitle = item.title
        }
        .onChange(of: item.title) { _, newValue in
            draftTitle = newValue
        }
    }

    private var itemMenu: some View {
        Menu {
            Button {
                store.toggleInboxItem(item)
            } label: {
                Label(
                    item.isCompleted
                        ? AppStrings.localized("inbox.markOpen")
                        : AppStrings.localized("inbox.markCompleted"),
                    systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                )
            }

            Button(role: .destructive) {
                requestDelete()
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(AppStrings.localized("common.more"))
    }

    @ViewBuilder
    private var suggestionBar: some View {
        if item.isCompleted {
            EmptyView()
        } else if store.inboxSuggestionInFlightIDs.contains(item.id) {
            InboxGeneratingSuggestionBar()
        } else if store.inboxSuggestionFailureMessage(for: item) != nil {
            InboxSuggestionFailureBar(
                isCompact: isCompact,
                retry: {
                    store.retryInboxSuggestion(item)
                },
                discard: {
                    store.clearInboxSuggestionFailure(item)
                }
            )
        } else if let suggestion, let task = store.task(for: suggestion.taskID) {
            InboxSuggestionBar(
                taskTitle: task.title,
                isCompact: isCompact,
                discard: {
                    store.discardInboxSuggestion(item)
                },
                apply: {
                    store.applyInboxSuggestion(item)
                }
            )
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
