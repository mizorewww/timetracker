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
                QuickStartTaskButton(task: task, isRunning: activeSegment != nil) {
                    if let activeSegment {
                        store.stop(segment: activeSegment)
                    } else {
                        store.startTask(task)
                    }
                }
            }
        }
    }
}

private struct QuickStartTaskButton: View {
    let task: TaskNode
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
                        Spacer(minLength: 0)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color(hex: task.colorHex) ?? .blue)
        .accessibilityLabel(task.title)
        .accessibilityValue(isRunning ? AppStrings.localized("status.running") : task.status.displayName)
        .accessibilityHint(
            AppStrings.localized(isRunning ? "timer.task.stopHint" : "timer.task.startHint")
        )
    }

    private var taskIcon: some View {
        Image(systemName: isRunning ? "stop.fill" : (task.iconName ?? "play"))
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(isRunning ? .red : (Color(hex: task.colorHex) ?? .blue))
            .frame(width: 20)
    }

    private var taskTitle: some View {
        Text(task.title)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
