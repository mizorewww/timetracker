import SwiftUI

struct InboxView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draftTitle = ""
    @State private var addFocusToken = 0
    @State private var isSorting = false
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
        ScrollView {
            VStack(alignment: .leading, spacing: isCompact ? 14 : 24) {
                header
                inboxCard
                footerHint
            }
            .frame(maxWidth: isCompact ? .infinity : 1100, alignment: .leading)
            .padding(.horizontal, isCompact ? 28 : 34)
            .padding(.top, isCompact ? 18 : 28)
            .padding(.bottom, 34)
        }
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(isCompact ? "" : AppStrings.inbox)
        #if os(iOS)
        .toolbar(isCompact ? .hidden : .visible, for: .navigationBar)
        .navigationBarTitleDisplayMode(.inline)
        #endif
    }

    private var inboxCard: some View {
        VStack(spacing: 0) {
            InboxCaptureRow(
                title: $draftTitle,
                placeholder: AppStrings.localized("inbox.addPlaceholder"),
                focusToken: addFocusToken,
                isCompact: isCompact,
                submit: submitDraft
            )
            .padding(.horizontal, isCompact ? 14 : 18)
            .padding(.top, isCompact ? 14 : 18)
            .padding(.bottom, isCompact ? 16 : 18)

            if openItems.isEmpty && completedItems.isEmpty {
                Divider()
                    .padding(.horizontal, isCompact ? 14 : 18)
                EmptyStateRow(
                    title: AppStrings.localized("inbox.empty"),
                    icon: "tray"
                )
                .padding(.horizontal, isCompact ? 14 : 18)
                .padding(.vertical, 24)
            } else {
                Divider()
                    .padding(.horizontal, isCompact ? 14 : 18)
                itemList
                    .frame(height: itemListHeight)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: isCompact ? 28 : 24, style: .continuous)
                .fill(AppColors.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: isCompact ? 28 : 24, style: .continuous)
                .stroke(AppColors.border.opacity(0.55))
        }
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
        guard !item.isCompleted else {
            return isCompact ? 78 : 82
        }
        if store.inboxSuggestionInFlightIDs.contains(item.id) || store.inboxSuggestion(for: item) != nil {
            return isCompact ? 142 : 132
        }
        return isCompact ? 78 : 82
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
                    .lineLimit(isCompact ? 2 : nil)
                    .minimumScaleFactor(isCompact ? 0.88 : 1)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            Button {
                addFocusToken += 1
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: isCompact ? 23 : 20, weight: .regular))
                    .foregroundStyle(.blue)
                    .frame(width: isCompact ? 54 : 44, height: isCompact ? 54 : 44)
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
        InboxItemRow(
            store: store,
            item: item,
            isCompact: isCompact,
            isSorting: isSorting,
            canSort: openItems.count > 1,
            toggleSorting: toggleSorting
        )
            .padding(.vertical, isCompact ? 8 : 10)
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
            leading: isCompact ? 14 : 18,
            bottom: bottom,
            trailing: isCompact ? 14 : 18
        )
    }

    private func toggleSorting() {
        #if os(iOS)
        withAnimation(.snappy(duration: 0.2)) {
            isSorting.toggle()
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
    let isCompact: Bool
    let submit: () -> Bool
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 10) {
            Button(action: addButtonTapped) {
                Image(systemName: "plus")
                    .font(.system(size: isCompact ? 16 : 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: isCompact ? 26 : 34, height: isCompact ? 26 : 34)
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
        .frame(minHeight: isCompact ? 48 : 52)
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
    let isSorting: Bool
    let canSort: Bool
    let toggleSorting: () -> Void
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
    let taskTitle: String
    let isCompact: Bool
    let discard: () -> Void
    let apply: () -> Void

    var body: some View {
        horizontalLayout
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(suggestionBackground)
    }

    private var horizontalLayout: some View {
        HStack(spacing: isCompact ? 6 : 10) {
            suggestionLabel
                .layoutPriority(1)
            Spacer(minLength: isCompact ? 4 : 8)
            actions
                .fixedSize()
        }
    }

    private var suggestionLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles")
                .font(.body.weight(.semibold))
                .foregroundStyle(.blue)

            Text(AppStrings.localized("inbox.suggestion.prefix"))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)

            Text(taskTitle)
                .fontWeight(.semibold)
                .foregroundStyle(.blue)
                .lineLimit(1)
                .truncationMode(.tail)
                .layoutPriority(1)
        }
        .font(.subheadline)
        .minimumScaleFactor(0.78)
    }

    private var actions: some View {
        HStack(spacing: isCompact ? 8 : 12) {
            Button(role: .destructive, action: discard) {
                Image(systemName: "xmark")
                    .font(.system(size: isCompact ? 13 : 14, weight: .semibold))
                    .foregroundStyle(.red)
                    .frame(width: isCompact ? 34 : 38, height: isCompact ? 34 : 38)
                    .background(Color.secondary.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(action: apply) {
                Image(systemName: "checkmark")
                    .font(.system(size: isCompact ? 14 : 15, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: isCompact ? 34 : 38, height: isCompact ? 34 : 38)
                    .background(Color.blue, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.apply"))
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
