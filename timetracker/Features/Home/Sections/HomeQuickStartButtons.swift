import SwiftUI

struct QuickStartTaskGroup: View {
    let tasks: [TaskNode]
    let store: TimeTrackerStore
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: dynamicTypeSize.isAccessibilitySize ? 300 : 180), spacing: 12)]
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            ForEach(tasks, id: \.id) { task in
                let activeSegment = store.activeSegment(for: task.id)
                QuickStartTaskButton(
                    presentation: store.taskIdentityPresentation(for: task),
                    isRunning: activeSegment != nil
                ) {
                    if activeSegment != nil {
                        store.openTaskDetail(task.id)
                    } else {
                        store.startTask(task)
                    }
                }
            }
        }
    }
}

private struct QuickStartTaskButton: View {
    let presentation: TaskIdentityPresentation
    let isRunning: Bool
    let action: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 8) {
                        taskIcon
                        taskTitle
                    }
                } else {
                    HStack(spacing: 8) {
                        taskIcon
                        taskTitle
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color(hex: presentation.visual.colorHex) ?? .blue)
        .accessibilityLabel(presentation.title)
        .accessibilityValue(
            isRunning
                ? AppStrings.localized("status.running")
                : (presentation.parentPath ?? "")
        )
        .accessibilityHint(
            AppStrings.localized(isRunning ? "timer.task.openRunningHint" : "timer.task.startHint")
        )
        .accessibilityIdentifier("home.quickStart.task.\(presentation.id.uuidString)")
    }

    private var taskIcon: some View {
        TaskIcon(visual: presentation.visual, size: 32)
    }

    private var taskTitle: some View {
        let text = presentation.text(for: .standard)
        return HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(text.primary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let secondary = text.secondary {
                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                }
            }
            Spacer(minLength: 4)
            if isRunning {
                RunningStatusBadge()
            } else {
                Image(systemName: "play.fill")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
