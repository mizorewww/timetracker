import SwiftUI

struct InboxView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draftTitle = ""
    @State private var addFocusToken = 0
    #if os(iOS)
    @Environment(\.editMode) private var editMode
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
        List {
            header
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: isCompact ? 14 : 24, leading: isCompact ? 22 : 32, bottom: 8, trailing: isCompact ? 22 : 32))

            Section {
                InboxCaptureRow(
                    title: $draftTitle,
                    placeholder: AppStrings.localized("inbox.addPlaceholder"),
                    focusToken: addFocusToken,
                    submit: submitDraft
                )
                .listRowSeparator(.hidden)
                .listRowInsets(cardRowInsets(top: isCompact ? 14 : 18, bottom: isCompact ? 14 : 18))
                .moveDisabled(true)

                if openItems.isEmpty && completedItems.isEmpty {
                    EmptyStateRow(
                        title: AppStrings.localized("inbox.empty"),
                        icon: "tray"
                    )
                    .listRowInsets(cardRowInsets())
                    .moveDisabled(true)
                } else {
                    ForEach(openItems) { item in
                        inboxRow(item)
                    }
                    .onMove(perform: moveInboxItems)

                    ForEach(completedItems) { item in
                        inboxRow(item)
                            .moveDisabled(true)
                    }
                }
            } header: {
                EmptyView()
            }
            .listRowBackground(AppColors.cardBackground)

            footerHint
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 14, leading: isCompact ? 22 : 32, bottom: 28, trailing: isCompact ? 22 : 32))
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(isCompact ? "" : AppStrings.inbox)
        #if os(iOS)
        .toolbar {
            if !openItems.isEmpty {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        toggleSorting()
                    } label: {
                        Label(AppStrings.localized("common.sort"), systemImage: isSorting ? "checkmark" : "arrow.up.arrow.down")
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel(isSorting ? AppStrings.done : AppStrings.localized("common.sort"))
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                if isCompact {
                    Text(AppStrings.inbox)
                        .font(.largeTitle.bold())
                } else {
                    Label {
                        Text(AppStrings.inbox)
                            .font(.title.bold())
                    } icon: {
                        Image(systemName: "tray")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.blue)
                    }
                }

                Text(.app("inbox.subtitle"))
                    .font(isCompact ? .callout : .body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                addFocusToken += 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: isCompact ? 24 : 20, weight: .regular))
                    .foregroundStyle(.blue)
                    .frame(width: isCompact ? 56 : 44, height: isCompact ? 56 : 44)
                    .background(.regularMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.add"))
        }
    }

    private var footerHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "lightbulb")
                .font(.body)
                .foregroundStyle(.blue)
                .frame(width: 22)
            Text(.app("inbox.footer"))
                .font(isCompact ? .callout : .body)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, isCompact ? 2 : 4)
    }

    @ViewBuilder
    private func inboxRow(_ item: InboxItem) -> some View {
        InboxItemRow(store: store, item: item, isCompact: isCompact)
            .padding(.vertical, isCompact ? 8 : 10)
            .listRowInsets(cardRowInsets())
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
            leading: isCompact ? 16 : 20,
            bottom: bottom,
            trailing: isCompact ? 16 : 20
        )
    }

    private var isSorting: Bool {
        #if os(iOS)
        editMode?.wrappedValue.isEditing == true
        #else
        false
        #endif
    }

    private func toggleSorting() {
        #if os(iOS)
        withAnimation(.snappy(duration: 0.2)) {
            editMode?.wrappedValue = isSorting ? .inactive : .active
        }
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
            (store.inboxSuggestionInFlightIDs.contains(item.id) || store.inboxSuggestion(for: item) != nil)
    }

    @discardableResult
    private func submitDraft() -> Bool {
        let title = draftTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else {
            addFocusToken += 1
            return false
        }
        store.addInboxItem(title: title)
        draftTitle = ""
        addFocusToken += 1
        return true
    }
}

private struct InboxCaptureRow: View {
    @Binding var title: String
    let placeholder: String
    var focusToken: Int
    let submit: () -> Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: addButtonTapped) {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.add"))

            TextField(placeholder, text: $title)
                .textFieldStyle(.plain)
                .font(.body)
                .focused($isFocused)
                .submitLabel(.done)
                .onSubmit(submitIfNeeded)
                .labelsHidden()

            Spacer(minLength: 8)

            Image(systemName: "keyboard")
                .font(.body)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .frame(minHeight: 52)
        .background(
            RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                .fill(AppColors.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                .stroke(AppColors.border)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            isFocused = true
        }
        .onChange(of: focusToken) { _, _ in
            isFocused = true
        }
        .onChange(of: title) { _, newValue in
            guard newValue.contains(where: \.isNewline) else { return }
            title = ChecklistInputTextNormalizer.collapsingNewlines(in: newValue)
            submitIfNeeded()
        }
    }

    private func submitIfNeeded() {
        guard !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        if submit() {
            title = ""
        }
        isFocused = true
    }

    private func addButtonTapped() {
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            isFocused = true
        } else {
            if submit() {
                title = ""
            }
            isFocused = true
        }
    }
}

private struct InboxItemRow: View {
    @ObservedObject var store: TimeTrackerStore
    let item: InboxItem
    let isCompact: Bool
    @State private var draftTitle = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
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
                store.deleteInboxItem(item)
            } label: {
                Label(AppStrings.delete, systemImage: "trash")
            }
        }
    }

    private var itemMenu: some View {
        Menu {
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
        } label: {
            Label(AppStrings.localized("common.more"), systemImage: "ellipsis")
                .labelStyle(.iconOnly)
                .font(.title3.weight(.semibold))
                .foregroundStyle(.secondary)
                .frame(width: 36, height: 36)
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
        } else if let suggestion, let task = store.task(for: suggestion.taskID) {
            InboxSuggestionBar(
                taskPath: store.taskPath(for: task),
                iconName: suggestion.iconName,
                colorHex: suggestion.colorHex,
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

private struct InboxGeneratingSuggestionBar: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(.blue)
            Text(.app("inbox.suggestion.generating"))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
            ProgressView()
                .controlSize(.small)
        }
        .font(.subheadline)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(suggestionBackground)
    }
}

private struct InboxSuggestionBar: View {
    let taskPath: String
    let iconName: String
    let colorHex: String
    let isCompact: Bool
    let discard: () -> Void
    let apply: () -> Void

    var body: some View {
        ViewThatFits(in: .horizontal) {
            horizontalLayout
            verticalLayout
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(suggestionBackground)
    }

    private var horizontalLayout: some View {
        HStack(spacing: isCompact ? 8 : 10) {
            suggestionLabel
            Spacer(minLength: 8)
            actions
        }
    }

    private var verticalLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            suggestionLabel
            HStack {
                Spacer(minLength: 0)
                actions
            }
        }
    }

    private var suggestionLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)

            Text(AppStrings.localized("inbox.suggestion.prefix"))
                .foregroundStyle(.secondary)

            Image(systemName: ChecklistVisualSanitizer.sanitizedIcon(iconName))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Color(hex: ChecklistVisualSanitizer.sanitizedColor(colorHex)) ?? .blue)

            Text(taskPath)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.middle)
                .layoutPriority(1)
        }
        .font(.subheadline)
        .minimumScaleFactor(0.88)
    }

    private var actions: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Button(role: .destructive, action: discard) {
                Label(AppStrings.localized("inbox.suggestion.discard"), systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .font(.subheadline.weight(.semibold))
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.small)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(action: apply) {
                Label(AppStrings.localized("inbox.suggestion.apply"), systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: isCompact ? 118 : 142, minHeight: 34)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.small)
        }
    }
}

private var suggestionBackground: some View {
    RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
        .fill(AppColors.cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                .stroke(AppColors.border)
        }
}
