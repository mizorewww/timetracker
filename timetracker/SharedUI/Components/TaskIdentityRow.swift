import SwiftUI

struct TaskIdentityRow: View {
    let presentation: TaskIdentityPresentation
    var context: TaskIdentityPresentation.Context = .standard
    var iconSize: CGFloat = 28

    var body: some View {
        TaskSummaryRow(
            presentation: presentation,
            context: context,
            iconSize: iconSize
        )
    }
}
