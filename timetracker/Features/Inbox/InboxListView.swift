import SwiftUI

struct InboxListRow: View {
    let store: TimeTrackerStore
    let item: InboxItem
    let isCompact: Bool
    @State private var isDeleteConfirmationPresented = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        InboxItemRow(
            store: store,
            item: item,
            isCompact: isCompact,
            requestDelete: requestDelete
        )
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if let action = applicableSuggestionAction {
                Button {
                    performAnimated {
                        store.applyInboxSuggestion(baseline: action.baseline)
                    }
                } label: {
                    Label(action.destination.applyTitle, systemImage: "checkmark")
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
                    performAnimated {
                        store.discardInboxSuggestion(item)
                    }
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
                performAnimated {
                    store.deleteInboxItem(item)
                }
            }
            Button(AppStrings.cancel, role: .cancel) {}
        } message: {
            Text(.app("inbox.delete.confirm.message"))
        }
    }

    private func performAnimated(_ action: () -> Void) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            action()
        }
    }

    private func requestDelete() {
        isDeleteConfirmationPresented = true
    }

    private var applicableSuggestionAction: ApplicableSuggestionAction? {
        guard !item.isCompleted,
              let suggestion = store.inboxSuggestion(for: item) else {
            return nil
        }
        let destination = store.inboxSuggestionDestinationPresentation(
            for: suggestion
        )
        guard destination.isAvailable else { return nil }
        return ApplicableSuggestionAction(
            destination: destination,
            baseline: InboxSuggestionApplyBaseline(
                item: item,
                suggestion: suggestion
            )
        )
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

private struct ApplicableSuggestionAction {
    let destination: InboxSuggestionDestinationPresentation
    let baseline: InboxSuggestionApplyBaseline
}
