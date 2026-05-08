import SwiftUI

struct InboxView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var draftTitle = ""
    @State private var addFocusToken = 0
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
                InboxListView(
                    store: store,
                    openItems: openItems,
                    completedItems: completedItems,
                    isCompact: isCompact
                )
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
