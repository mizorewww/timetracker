import SwiftUI

struct InboxListRow: View {
    let store: TimeTrackerStore
    let item: InboxItem
    let isCompact: Bool
    @State private var isDeleteConfirmationPresented = false

    var body: some View {
        InboxItemRow(
            store: store,
            item: item,
            isCompact: isCompact,
            requestDelete: requestDelete
        )
        .padding(.vertical, 2)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if canApplySuggestion {
                Button {
                    store.applyInboxSuggestion(item)
                } label: {
                    Label(AppStrings.localized("inbox.suggestion.apply"), systemImage: "checkmark")
                }
                .tint(.blue)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                requestDelete()
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }

            if canDiscardSuggestion {
                Button {
                    store.discardInboxSuggestion(item)
                } label: {
                    Label(AppStrings.localized("inbox.suggestion.discard"), systemImage: "xmark")
                }
                .tint(.gray)
            }
        }
        .confirmationDialog(
            AppStrings.localized("inbox.delete.confirm.title"),
            isPresented: $isDeleteConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(AppStrings.delete, role: .destructive) {
                store.deleteInboxItem(item)
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("inbox.delete.confirm.message"))
        }
    }

    private func requestDelete() {
        isDeleteConfirmationPresented = true
    }

    private var canApplySuggestion: Bool {
        guard !item.isCompleted,
              let suggestion = store.inboxSuggestion(for: item),
              store.task(for: suggestion.taskID) != nil else {
            return false
        }
        return true
    }

    private var canDiscardSuggestion: Bool {
        !item.isCompleted &&
            (
                store.inboxSuggestionInFlightIDs.contains(item.id) ||
                store.inboxSuggestion(for: item) != nil ||
                store.inboxSuggestionFailureMessage(for: item) != nil
            )
    }
}
