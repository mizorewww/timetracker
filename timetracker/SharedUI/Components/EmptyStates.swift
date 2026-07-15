import SwiftUI

struct EmptyStateRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
                .accessibilityHidden(true)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
    }
}
