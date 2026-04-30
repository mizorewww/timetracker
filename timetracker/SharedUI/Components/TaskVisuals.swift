import SwiftUI

struct TaskIcon: View {
    let task: TaskNode?
    var size: CGFloat = 38

    var body: some View {
        let tint = Color(hex: task?.colorHex) ?? .blue
        Image(systemName: task?.iconName ?? "checkmark.circle")
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppLayout.iconRadius, style: .continuous))
    }
}
