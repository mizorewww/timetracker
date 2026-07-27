import SwiftUI

struct InfoRow: View {
    let title: String
    let value: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleText
                    .frame(minWidth: 54, maxWidth: 112, alignment: .leading)
                Spacer(minLength: 8)
                valueText
                    .multilineTextAlignment(.trailing)
            }

            VStack(alignment: .leading, spacing: 4) {
                titleText
                valueText
            }
        }
        .font(rowFont)
        .accessibilityElement(children: .combine)
    }

    private var rowFont: Font {
        #if os(macOS)
        .body
        #else
        .subheadline
        #endif
    }

    private var titleText: some View {
        Text(title)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var valueText: some View {
        Text(value)
            .foregroundStyle(.primary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
