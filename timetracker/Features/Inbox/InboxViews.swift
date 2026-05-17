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

    private var layout: InboxLayoutPolicy {
        #if os(iOS)
        InboxLayoutPolicy(horizontalSizeClass: horizontalSizeClass)
        #else
        InboxLayoutPolicy(horizontalSizeClass: nil)
        #endif
    }

    private var isCompact: Bool {
        layout.isCompact
    }

    private var bottomPadding: CGFloat {
        #if os(iOS)
        isCompact ? PhoneRootChromeMetrics.scrollBottomClearance : 34
        #else
        34
        #endif
    }

    private var horizontalPadding: CGFloat {
        #if os(iOS)
        isCompact ? PhoneRootChromeMetrics.pageHorizontalPadding : layout.pageHorizontalPadding
        #else
        layout.pageHorizontalPadding
        #endif
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: layout.contentSpacing) {
                #if os(iOS)
                if isCompact {
                    PhoneLargePageHeader(destination: .inbox)
                }
                #endif
                header
                inboxCard
                footerHint
            }
            .frame(maxWidth: layout.contentMaxWidth ?? .infinity, alignment: .leading)
            .padding(.horizontal, horizontalPadding)
            .padding(.top, layout.pageTopPadding)
            .padding(.bottom, bottomPadding)
        }
        #if os(iOS)
        .phoneRootScrollBehavior(enabled: isCompact)
        #endif
        .scrollContentBackground(.hidden)
        .background(AppColors.background.ignoresSafeArea())
        .accessibilityIdentifier("inbox.view")
        .navigationTitle(AppStrings.inbox)
        #if os(iOS)
        .navigationBarTitleDisplayMode(isCompact ? .inline : .large)
        .toolbar {
            if isCompact {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        addFocusToken += 1
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel(AppStrings.localized("inbox.add"))
                    .accessibilityIdentifier("inbox.add")
                }
            }
        }
        .phoneChromeScrollObserver(destination: .inbox, enabled: isCompact)
        .phoneRootChrome(destination: .inbox, enabled: isCompact)
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
            .padding(.horizontal, layout.cardHorizontalPadding)
            .padding(.top, layout.captureTopPadding)
            .padding(.bottom, layout.captureBottomPadding)

            if openItems.isEmpty && completedItems.isEmpty {
                Divider()
                    .padding(.horizontal, layout.cardHorizontalPadding)
                EmptyStateRow(
                    title: AppStrings.localized("inbox.empty"),
                    icon: "tray"
                )
                .padding(.horizontal, layout.cardHorizontalPadding)
                .padding(.vertical, 24)
            } else {
                Divider()
                    .padding(.horizontal, layout.cardHorizontalPadding)
                InboxListView(
                    store: store,
                    openItems: openItems,
                    completedItems: completedItems,
                    layout: layout
                )
            }
        }
        .background(
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .fill(AppColors.cardBackground)
        )
        .overlay {
            RoundedRectangle(cornerRadius: layout.cardCornerRadius, style: .continuous)
                .stroke(AppColors.border.opacity(0.55))
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: isCompact ? 8 : 12) {
                if !isCompact {
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

            if !isCompact {
                Button {
                    addFocusToken += 1
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.blue)
                        .frame(width: 44, height: 44)
                        .background(.regularMaterial, in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppStrings.localized("inbox.add"))
                .accessibilityIdentifier("inbox.add")
            }
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
