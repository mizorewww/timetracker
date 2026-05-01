import SwiftUI

struct InboxView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draftTitle = ""
    @State private var addFocusToken = 0
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var items: [InboxItem] {
        store.inboxItemsForDisplay
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
            VStack(alignment: .leading, spacing: isCompact ? 18 : 24) {
                header
                inboxCard
                footerHint
            }
            .frame(maxWidth: isCompact ? .infinity : 1_060, alignment: .leading)
            .padding(.horizontal, isCompact ? 22 : 32)
            .padding(.top, isCompact ? 14 : 28)
            .padding(.bottom, 36)
            .frame(maxWidth: .infinity, alignment: .top)
        }
        .background(AppColors.background.ignoresSafeArea())
        .navigationTitle(isCompact ? "" : AppStrings.inbox)
        #if os(iOS)
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
                Label(AppStrings.localized("inbox.add"), systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: isCompact ? 22 : 20, weight: .regular))
                    .frame(width: isCompact ? 48 : 44, height: isCompact ? 48 : 44)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.large)
            .tint(.blue)
            .accessibilityLabel(AppStrings.localized("inbox.add"))
        }
    }

    private var inboxCard: some View {
        VStack(spacing: 0) {
            InboxCaptureRow(
                title: $draftTitle,
                placeholder: AppStrings.localized("inbox.addPlaceholder"),
                focusToken: addFocusToken,
                submit: submitDraft
            )
            .padding(.bottom, 16)

            Divider()

            if items.isEmpty {
                EmptyStateRow(
                    title: AppStrings.localized("inbox.empty"),
                    icon: "tray"
                )
                .padding(.top, 16)
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        if index > 0 {
                            Divider()
                        }
                        InboxItemRow(store: store, item: item, isCompact: isCompact)
                            .padding(.vertical, isCompact ? 14 : 16)
                    }
                }
            }
        }
        .padding(isCompact ? 14 : 22)
        .background(AppColors.cardBackground, in: RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                .stroke(AppColors.border)
        }
        .shadow(color: .black.opacity(isCompact ? 0.06 : 0.05), radius: isCompact ? 18 : 22, x: 0, y: 10)
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
                Label(AppStrings.localized("inbox.add"), systemImage: "plus")
                    .labelStyle(.iconOnly)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .tint(.blue)

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
                    .font(.headline.weight(.semibold))
                    .frame(width: 38, height: 38)
            }
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .controlSize(.regular)
            .accessibilityLabel(AppStrings.localized("inbox.suggestion.discard"))

            Button(action: apply) {
                Label(AppStrings.localized("inbox.suggestion.apply"), systemImage: "checkmark")
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(minWidth: isCompact ? 126 : 150, minHeight: 38)
            }
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .controlSize(.regular)
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
