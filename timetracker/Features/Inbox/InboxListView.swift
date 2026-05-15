import SwiftUI

struct InboxListView: View {
    @ObservedObject var store: TimeTrackerStore
    let openItems: [InboxItem]
    let completedItems: [InboxItem]
    let layout: InboxLayoutPolicy
    @State private var isSorting = false

    private var isCompact: Bool {
        layout.isCompact
    }

    var body: some View {
        itemList
            .frame(height: itemListHeight)
    }

    @ViewBuilder
    private var itemList: some View {
        let list = List {
            ForEach(openItems) { item in
                inboxRow(item)
            }
            .onMove(perform: moveInboxItems)

            ForEach(completedItems) { item in
                inboxRow(item)
                    .moveDisabled(true)
            }
        }
        .listStyle(.plain)
        .scrollDisabled(true)
        .scrollContentBackground(.hidden)
        .background(Color.clear)

        #if os(iOS)
        list.environment(\.editMode, .constant(isSorting ? EditMode.active : EditMode.inactive))
        #else
        list
        #endif
    }

    private var itemListHeight: CGFloat {
        let rows = openItems + completedItems
        guard !rows.isEmpty else { return 0 }
        return rows.reduce(CGFloat.zero) { total, item in
            total + rowHeight(for: item)
        }
    }

    private func rowHeight(for item: InboxItem) -> CGFloat {
        let hasSupplementaryContent = store.inboxSuggestionInFlightIDs.contains(item.id) ||
            store.inboxSuggestion(for: item) != nil ||
            store.inboxSuggestionFailureMessage(for: item) != nil
        return layout.rowHeight(
            forTitle: item.title,
            isCompleted: item.isCompleted,
            hasSupplementaryContent: hasSupplementaryContent
        )
    }

    @ViewBuilder
    private func inboxRow(_ item: InboxItem) -> some View {
        InboxItemRow(
            store: store,
            item: item,
            isCompact: isCompact,
            isSorting: isSorting,
            canSort: openItems.count > 1,
            toggleSorting: toggleSorting
        )
        .padding(.vertical, layout.rowVerticalPadding)
        .listRowInsets(cardRowInsets())
        .listRowBackground(Color.clear)
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if canApplySuggestion(for: item) {
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
                store.deleteInboxItem(item)
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }

            if canDiscardSuggestion(for: item) {
                Button {
                    store.discardInboxSuggestion(item)
                } label: {
                    Label(AppStrings.localized("inbox.suggestion.discard"), systemImage: "xmark")
                }
                .tint(.gray)
            }
        }
    }

    private func cardRowInsets(top: CGFloat = 0, bottom: CGFloat = 0) -> EdgeInsets {
        EdgeInsets(
            top: top,
            leading: layout.cardHorizontalPadding,
            bottom: bottom,
            trailing: layout.cardHorizontalPadding
        )
    }

    private func toggleSorting() {
        #if os(iOS)
        isSorting.toggle()
        #endif
    }

    private func moveInboxItems(from sourceOffsets: IndexSet, to destination: Int) {
        store.reorderInboxItems(sourceOffsets: sourceOffsets, destination: destination)
    }

    private func canApplySuggestion(for item: InboxItem) -> Bool {
        guard !item.isCompleted,
              let suggestion = store.inboxSuggestion(for: item),
              store.task(for: suggestion.taskID) != nil else {
            return false
        }
        return true
    }

    private func canDiscardSuggestion(for item: InboxItem) -> Bool {
        !item.isCompleted &&
            (
                store.inboxSuggestionInFlightIDs.contains(item.id) ||
                store.inboxSuggestion(for: item) != nil ||
                store.inboxSuggestionFailureMessage(for: item) != nil
            )
    }
}
