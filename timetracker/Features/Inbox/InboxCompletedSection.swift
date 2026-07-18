import SwiftUI

struct InboxCompletedSection: View {
    let store: TimeTrackerStore
    let items: [InboxItem]
    let isCompact: Bool
    @Binding var isExpanded: Bool

    var body: some View {
        Section {
            if isExpanded {
                ForEach(items) { item in
                    InboxListRow(
                        store: store,
                        item: item,
                        isCompact: isCompact
                    )
                    .moveDisabled(true)
                }
            }
        } header: {
            Button {
                isExpanded.toggle()
            } label: {
                HStack(spacing: 8) {
                    Text(completedLabel)
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.forward")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(completedLabel)
            .accessibilityHint(
                AppStrings.localized(isExpanded ? "tasks.collapse" : "tasks.expand")
            )
            .accessibilityIdentifier("inbox.completed.disclosure")
        }
    }

    private var completedLabel: String {
        String.localizedStringWithFormat(
            AppStrings.localized("inbox.completed.countFormat"),
            items.count
        )
    }
}
