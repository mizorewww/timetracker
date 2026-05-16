import SwiftUI

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .foregroundStyle(.secondary)
                .frame(minWidth: 54, maxWidth: 86, alignment: .leading)
            Spacer()
            Text(value)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .font(.subheadline)
    }
}
