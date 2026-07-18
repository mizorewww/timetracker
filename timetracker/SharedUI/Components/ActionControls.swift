import SwiftUI

struct AppActionLabel: View {
    let title: String
    let systemImage: String
    var fixedHeight: CGFloat?
    var minHeight: CGFloat = 44
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .frame(height: dynamicTypeSize.isAccessibilitySize ? nil : fixedHeight)
        .frame(
            minHeight: dynamicTypeSize.isAccessibilitySize || fixedHeight == nil
                ? minHeight
                : 0
        )
        .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 0)
        .contentShape(Rectangle())
    }
}

struct TrailingMenuLabel: View {
    let systemImage: String

    var body: some View {
        Image(systemName: systemImage)
            .frame(
                minWidth: AppLayout.minimumInteractiveTarget,
                minHeight: AppLayout.minimumInteractiveTarget,
                alignment: .trailing
            )
            .contentShape(Rectangle())
    }
}
