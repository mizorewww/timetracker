import SwiftUI

struct QuickStartTaskGroup: View {
    let title: String
    let tasks: [TaskNode]
    @ObservedObject var store: TimeTrackerStore

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 12)]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(tasks, id: \.id) { task in
                    QuickStartTaskButton(task: task) {
                        store.startTask(task)
                    }
                }
            }
        }
    }
}

private struct QuickStartTaskButton: View {
    let task: TaskNode
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: task.iconName ?? "play")
                    .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
                    .frame(width: 18)
                Text(task.title)
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .controlSize(.large)
        .tint(Color(hex: task.colorHex) ?? .blue)
    }
}
