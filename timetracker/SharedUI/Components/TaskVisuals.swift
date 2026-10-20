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
        AppIconTile(
            systemImage: visual.symbolName,
            tint: Color(hex: visual.colorHex) ?? .blue,
            size: size
        )
    }
}
