import SwiftUI

struct CompactTextActionLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .frame(
                minWidth: AppLayout.minimumInteractiveTarget,
                minHeight: AppLayout.minimumInteractiveTarget
            )
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
