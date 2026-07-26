import SwiftUI

struct InboxView: View {
    let store: TimeTrackerStore
    @State private var draft = InboxCaptureDraft()
    @State private var addFocusToken = 0
    @State private var isSorting = false
    @State private var showsCompleted = false
    @State private var completionPresentationRevision = 0
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.layoutShell) private var layoutShell

    private var openItems: [InboxItem] {
        store.openInboxItems
    }

    private var completedItems: [InboxItem] {
        store.completedInboxItems
    }

    /// Drives whether suggestion accept/dismiss render as icon-only circular
    /// buttons or as full labelled rows. Previously false on macOS at any
    /// width, which left a narrow Mac window trying to fit both labels.
    private var isCompact: Bool {
        horizontalSizeClass == .compact || layoutShell == .compact
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
            .navigationBarTitleDisplayMode(.large)
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
                .moveDisabled(true)
            }

            if !openItems.isEmpty {
                Section {
                    ForEach(openItems) { item in
                        InboxListRow(
                            store: store,
                            item: item,
                            isCompact: isCompact,
                            toggleCompletion: {
                                toggleCompletion(item.id)
                            }
                        )
                    }
                    .onMove(perform: moveInboxItems)
                }
            }

            if openItems.isEmpty, completedItems.isEmpty {
                Section {
                    emptyState
                        .frame(maxWidth: .infinity)
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                }
            }

            if !completedItems.isEmpty {
                InboxCompletedSection(
                    store: store,
                    items: completedItems,
                    isCompact: isCompact,
                    isExpanded: $showsCompleted,
                    toggleCompletion: toggleCompletion
                )
            }
        }
        .id(completionPresentationRevision)
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

    private func toggleCompletion(_ itemID: UUID) {
        guard let currentItem = store.inboxItems.first(where: { $0.id == itemID }) else {
            return
        }
        if currentItem.isCompleted == false {
            showsCompleted = true
        }
        store.toggleInboxItem(currentItem)
        completionPresentationRevision += 1
    }

    @discardableResult
    private func submitDraft() -> Bool {
        let didAdd = withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            draft.submit(using: store.addInboxItem(title:))
        }
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
