import SwiftUI

enum TaskIdentityRowState: Equatable {
    case normal
    case completed
    case blocked
}

struct TaskIdentityRow: View {
    let presentation: TaskIdentityPresentation
    var context: TaskIdentityPresentation.Context = .standard
    var state: TaskIdentityRowState = .normal
    var iconSize: CGFloat = 28

    var body: some View {
        let text = presentation.text(for: context)
        HStack(alignment: .top, spacing: 12) {
            TaskIcon(visual: presentation.visual, size: iconSize)

            VStack(alignment: .leading, spacing: 5) {
                Text(text.primary)
                    .font(.body.weight(.medium))
                    .foregroundStyle(state == .completed ? .secondary : .primary)
                    .strikethrough(state == .completed)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)

                if let secondary = text.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                switch state {
                case .normal:
                    EmptyView()
                case .completed:
                    TaskStatusBadge(status: .completed)
                case .blocked:
                    TaskWorkBlockedStatusBadge()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(
            maxWidth: .infinity,
            minHeight: minimumRowHeight,
            alignment: .leading
        )
        .accessibilityElement(children: .combine)
    }

    private var minimumRowHeight: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }
}
