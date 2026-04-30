import SwiftUI

struct EmptyStateRow: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .frame(width: 20)
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
