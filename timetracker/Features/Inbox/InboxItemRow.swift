import SwiftUI

struct InboxItemRow: View {
    let store: TimeTrackerStore
    let item: InboxItem
    let isCompact: Bool
    let isSorting: Bool
    let canSort: Bool
    let toggleSorting: () -> Void
    let requestDelete: () -> Void
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                EditableChecklistTextRow(
                    title: $draftTitle,
                    isCompleted: item.isCompleted,
                    iconName: rowIconName,
                    colorHex: rowColorHex,
                    placeholder: AppStrings.localized("inbox.itemPlaceholder"),
                    toggle: {
                        store.toggleInboxItem(item)
                    },
                    commit: commitTitleIfNeeded
                )

                itemMenu
                    .padding(.top, 5)
            }

            suggestionBar
        }
        .onAppear {
            draftTitle = item.title
        }
        .onChange(of: item.title) { _, newValue in
            draftTitle = newValue
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
                requestDelete()
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        }
    }

    private var itemMenu: some View {
        Menu {
            #if os(iOS)
            if canSort {
                Button {
                    toggleSorting()
                } label: {
                    Label(
                        isSorting ? AppStrings.done : AppStrings.localized("common.sort"),
                        systemImage: isSorting ? "checkmark" : "arrow.up.arrow.down"
                    )
                }
            }
            #endif

            Button {
                store.toggleInboxItem(item)
            } label: {
                Label(
                    item.isCompleted ? AppStrings.localized("inbox.markOpen") : AppStrings.localized("inbox.markCompleted"),
                    systemImage: item.isCompleted ? "circle" : "checkmark.circle"
                )
            }

            Button(role: .destructive) {
                requestDelete()
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        } label: {
            Label(AppStrings.localized("common.more"), systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
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

    private var rowIconName: String {
        guard let iconName = suggestion?.iconName,
              isGenericInboxSuggestionIcon(iconName) == false else {
            return "tray"
        }
        return iconName
    }

    private var rowColorHex: String {
        suggestion?.colorHex ?? ChecklistVisualSanitizer.defaultColor
    }

    private func commitTitleIfNeeded() {
        let normalizedDraft = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedDraft != item.title else { return }
        store.updateInboxItemTitle(item, title: normalizedDraft)
    }

    private func isGenericInboxSuggestionIcon(_ iconName: String?) -> Bool {
        let sanitized = ChecklistVisualSanitizer.sanitizedIcon(iconName)
        return [
            ChecklistVisualSanitizer.defaultIcon,
            "checkmark",
            "checkmark.circle",
            "checkmark.circle.fill",
            "circle",
            "circle.dashed"
        ].contains(sanitized)
    }
}
