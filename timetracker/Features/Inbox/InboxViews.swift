import SwiftUI

struct InboxView: View {
    let store: TimeTrackerStore
    @State private var draft = InboxCaptureDraft()
    @State private var addFocusToken = 0
    @State private var isSorting = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var openItems: [InboxItem] {
        store.openInboxItems
    }

    private var completedItems: [InboxItem] {
        store.completedInboxItems
    }

    private var isCompact: Bool {
        #if os(iOS)
        horizontalSizeClass == .compact
        #else
        false
        #endif
    }

    var body: some View {
        inboxList
            #if os(iOS)
            .environment(\.editMode, .constant(isSorting ? EditMode.active : EditMode.inactive))
            .listStyle(.insetGrouped)
            .scrollDismissesKeyboard(.interactively)
            #else
            .listStyle(.inset)
            #endif
            .scrollContentBackground(.hidden)
            .background(AppColors.background.ignoresSafeArea())
            .navigationTitle(AppStrings.inbox)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .accessibilityIdentifier("inbox.view")
            .toolbar {
                #if os(iOS)
                if openItems.count > 1 {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(action: toggleSorting) {
                            Label(
                                isSorting ? AppStrings.done : AppStrings.localized("common.sort"),
                                systemImage: isSorting ? "checkmark" : "arrow.up.arrow.down"
                            )
                            .labelStyle(.iconOnly)
                        }
                        .accessibilityIdentifier("inbox.sort")
                    }
                }
                #endif
            }
            .onChange(of: openItems.count) { _, count in
                if count < 2 {
                    isSorting = false
                }
            }
    }

    private var inboxList: some View {
        List {
            Section {
                InboxCaptureRow(
                    title: $draft.title,
                    placeholder: AppStrings.localized("inbox.addPlaceholder"),
                    focusToken: addFocusToken,
                    submit: submitDraft
                )
            }

            if openItems.isEmpty && completedItems.isEmpty {
                Section {
                    emptyState
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }
            } else {
                if !openItems.isEmpty {
                    Section {
                        ForEach(openItems) { item in
                            InboxListRow(
                                store: store,
                                item: item,
                                isCompact: isCompact,
                                isSorting: isSorting,
                                canSort: openItems.count > 1,
                                toggleSorting: toggleSorting
                            )
                        }
                        .onMove(perform: moveInboxItems)
                    }
                }

                if !completedItems.isEmpty {
                    Section {
                        ForEach(completedItems) { item in
                            InboxListRow(
                                store: store,
                                item: item,
                                isCompact: isCompact,
                                isSorting: isSorting,
                                canSort: false,
                                toggleSorting: toggleSorting
                            )
                            .moveDisabled(true)
                        }
                    } header: {
                        Text(.app("status.completed"))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Label {
                Text(.app("inbox.empty"))
                    .lineLimit(nil)
                    .fixedSize(horizontal: false, vertical: true)
            } icon: {
                Image(systemName: "tray")
            }
            .font(.headline)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
            .accessibilityHint(Text(.app("inbox.empty.description")))
        } else {
            ContentUnavailableView(
                AppStrings.localized("inbox.empty"),
                systemImage: "tray",
                description: Text(.app("inbox.empty.description"))
            )
        }
    }

    private func focusCaptureField() {
        addFocusToken += 1
    }

    private func toggleSorting() {
        #if os(iOS)
        isSorting.toggle()
        #endif
    }

    private func moveInboxItems(from sourceOffsets: IndexSet, to destination: Int) {
        store.reorderInboxItems(sourceOffsets: sourceOffsets, destination: destination)
    }

    @discardableResult
    private func submitDraft() -> Bool {
        let didAdd = draft.submit(using: store.addInboxItem(title:))
        focusCaptureField()
        return didAdd
    }
}

struct InboxCaptureDraft: Equatable {
    var title = ""

    mutating func submit(using addItem: (String) -> Bool) -> Bool {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty, addItem(normalizedTitle) else {
            return false
        }
        title = ""
        return true
    }
}
