import SwiftUI

struct TaskIcon: View {
    let visual: TaskVisualPresentation
    let size: CGFloat

    init(task: TaskNode?, size: CGFloat = 38) {
        visual = TaskVisualPresentation(
            iconName: task?.iconName,
            colorHex: task?.colorHex
        )
        self.size = size
    }

    init(visual: TaskVisualPresentation, size: CGFloat = 38) {
        self.visual = visual
        self.size = size
    }

    var body: some View {
        let tint = Color(hex: visual.colorHex) ?? .blue
        Image(systemName: visual.symbolName)
            .font(.system(size: size * 0.45, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppLayout.iconRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}
