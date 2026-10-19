import SwiftUI

enum InboxItemLayout {
    static let completionVisualSize: CGFloat = 24
    static let completionMarkLeadingInset = max(
        0,
        (AppLayout.minimumInteractiveTarget - completionVisualSize) / 2
    )
}

struct InboxItemRow: View {
    let store: TimeTrackerStore
    let item: InboxItem
    let isCompact: Bool
    let toggleCompletion: () -> Void
    let requestDelete: () -> Void
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppSceneFeedbackRouter.self) private var feedbackRouter
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 4) {
                EditableChecklistTextRow(
                    title: $draftTitle,
                    isCompleted: item.isCompleted,
                    placeholder: AppStrings.localized("inbox.itemPlaceholder"),
                    showsIcon: false,
                    completionVisualSize: InboxItemLayout.completionVisualSize,
                    textStyle: .body,
                    contentAlignment: .center,
                    completionAccessibilityIdentifier:
                    "inbox.item.completion.\(item.id.uuidString)",
                    textFieldAccessibilityIdentifier: "inbox.item.\(item.id.uuidString)",
                    persistedTitle: item.title,
                    toggle: {
                        toggleCompletion()
                    },
                    commit: commitTitleIfNeeded
                )

                itemMenu
            }

            suggestionBar
        }
        .animation(
            reduceMotion ? nil : AppMotion.stateChange,
            value: suggestionPresentationKey
        )
    }

    private var itemMenu: some View {
        Menu {
            Button {
                toggleCompletion()
            } label: {
                Label(
                    item.isCompleted
                        ? AppStrings.localized("inbox.markOpen")
                        : AppStrings.localized("inbox.markCompleted"),
                    systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                )
            }

            if item.isCompleted == false {
                Divider()

                Button(action: presentChildTaskParentPicker) {
                    Label(
                        AppStrings.localized("inbox.route.childTask"),
                        systemImage: "arrow.turn.down.right"
                    )
                }
                .accessibilityIdentifier(
                    "inbox.route.childTask.\(item.id.uuidString)"
                )

                Button(action: presentCategoryPicker) {
                    Label(
                        AppStrings.localized("inbox.route.categoryTask"),
                        systemImage: "square.grid.2x2"
                    )
                }
                .accessibilityIdentifier(
                    "inbox.route.categoryTask.\(item.id.uuidString)"
                )

                Button(action: presentChecklistTaskPicker) {
                    Label(
                        AppStrings.localized("inbox.route.checklistItem"),
                        systemImage: "checklist"
                    )
                }
                .accessibilityIdentifier(
                    "inbox.route.checklistItem.\(item.id.uuidString)"
                )
            }

            Divider()

            Button(role: .destructive) {
                requestDelete()
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        } label: {
            TrailingMenuLabel(systemImage: "ellipsis")
                .font(.body.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .menuIndicator(.hidden)
        .accessibilityLabel(AppStrings.localized("common.more"))
        .accessibilityIdentifier(
            "inbox.item.menu.\(item.id.uuidString)"
        )
    }

    private func presentChildTaskParentPicker() {
        let baseline = InboxManualRouteBaseline(item: item)
        presentationRouter.presentSingleTaskPicker(
            selectedTaskID: nil,
            context: .inboxChildTaskParent
        ) { parentTaskID in
            feedbackRouter.perform {
                try store.routeInboxItemAsChildTask(
                    baseline: baseline,
                    parentTaskID: parentTaskID
                )
            } ?? false
        }
    }

    private func presentCategoryPicker() {
        let baseline = InboxManualRouteBaseline(item: item)
        presentationRouter.presentSingleTaskCategoryPicker(
            selectedCategoryID: nil,
            context: .inboxTaskDestination
        ) { categoryID in
            feedbackRouter.perform {
                try store.routeInboxItemToCategory(
                    baseline: baseline,
                    categoryID: categoryID
                )
            } ?? false
        }
    }

    private func presentChecklistTaskPicker() {
        let baseline = InboxManualRouteBaseline(item: item)
        presentationRouter.presentSingleTaskPicker(
            selectedTaskID: nil,
            context: .inboxChecklistTarget
        ) { taskID in
            feedbackRouter.perform {
                try store.routeInboxItemAsChecklist(
                    baseline: baseline,
                    taskID: taskID
                )
            } ?? false
        }
    }

    @ViewBuilder
    private var suggestionBar: some View {
        if item.isCompleted {
            EmptyView()
        } else if store.inboxSuggestionInFlightIDs.contains(item.id) {
            InboxGeneratingSuggestionBar(itemID: item.id)
                .transition(suggestionTransition)
        } else if let failureMessage = store.inboxSuggestionFailureMessage(for: item) {
            InboxSuggestionFailureBar(
                itemID: item.id,
                message: failureMessage,
                isCompact: isCompact,
                retry: {
                    performAnimated {
                        store.retryInboxSuggestion(item)
                    }
                },
                discard: {
                    performAnimated {
                        store.clearInboxSuggestionFailure(item)
                    }
                }
            )
            .transition(suggestionTransition)
        } else if let suggestion {
            let applyBaseline = InboxSuggestionApplyBaseline(
                item: item,
                suggestion: suggestion
            )
            InboxSuggestionBar(
                itemID: item.id,
                destination: store.inboxSuggestionDestinationPresentation(
                    for: suggestion
                ),
                iconName: suggestion.iconName,
                colorHex: suggestion.colorHex,
                isCompact: isCompact,
                discard: {
                    performAnimated {
                        try store.discardInboxSuggestion(item)
                    }
                },
                apply: {
                    performAnimated {
                        try store.applyInboxSuggestion(baseline: applyBaseline)
                    }
                }
            )
            .transition(suggestionTransition)
        }
    }

    private var suggestionPresentationKey: String {
        if item.isCompleted {
            return "completed"
        }
        if store.inboxSuggestionInFlightIDs.contains(item.id) {
            return "generating"
        }
        if let message = store.inboxSuggestionFailureMessage(for: item) {
            return "failure:\(message)"
        }
        if let suggestion {
            return "ready:\(suggestion.id.uuidString):\(suggestion.clientMutationID.uuidString)"
        }
        return "none"
    }

    private var suggestionTransition: AnyTransition {
        reduceMotion
            ? .opacity
            : .opacity.combined(with: .move(edge: .top))
    }

    private var suggestion: InboxSuggestion? {
        store.inboxSuggestion(for: item)
    }

    private func performAnimated(_ action: () throws -> Void) {
        withAnimation(reduceMotion ? nil : AppMotion.stateChange) {
            feedbackRouter.perform(action)
        }
    }

    private func commitTitleIfNeeded() {
        let normalizedDraft = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDraft != item.title else { return }
        feedbackRouter.perform { try store.updateInboxItemTitle(item, title: normalizedDraft) }
    }
}
