import SwiftUI

struct AppActionLabel: View {
    let title: String
    let systemImage: String
    var fixedHeight: CGFloat?
    var minHeight: CGFloat = 44

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .frame(height: fixedHeight)
        .frame(minHeight: fixedHeight == nil ? minHeight : 0)
        .contentShape(Rectangle())
    }
}
