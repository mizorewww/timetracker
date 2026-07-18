import SwiftUI

struct WatchTaskShortcutRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let task: WatchRecentTaskSnapshot
    let commandState: WatchRowCommandState
    let isRunning: Bool
    let action: () -> Void

    private var tint: Color {
        Color(hex: task.colorHex) ?? .blue
    }

    var body: some View {
        Button(action: action) {
            Group {
                if usesStackedIdentity {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            taskIcon
                            Spacer(minLength: 4)
                            taskStateIcon
                        }
                        taskTitle
                    }
                } else {
                    HStack(spacing: 8) {
                        taskIcon
                        VStack(alignment: .leading, spacing: 3) {
                            taskTitle
                            taskPath
                        }
                        Spacer(minLength: 2)
                        taskStateIcon
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(commandState == .pending)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(Text(taskHintKey))
    }

    private var usesStackedIdentity: Bool {
        dynamicTypeSize >= .xxLarge
    }

    private var taskIcon: some View {
        WatchIconTile(systemImage: task.iconName ?? "play.fill", tint: tint)
    }

    private var taskTitle: some View {
        Text(task.title)
            .font(.headline)
            .lineLimit(usesStackedIdentity ? 3 : 2)
            .multilineTextAlignment(.leading)
            .privacySensitive()
            .redacted(reason: isLuminanceReduced ? .placeholder : [])
    }

    @ViewBuilder
    private var taskPath: some View {
        if !task.path.isEmpty {
            Text(task.path)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .privacySensitive()
                .redacted(reason: isLuminanceReduced ? .placeholder : [])
        }
    }

    private var taskStateIcon: some View {
        Image(systemName: taskSystemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(taskStateTint)
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        let identity = task.path.isEmpty ? task.title : "\(task.title), \(task.path)"
        let baseLabel = if isRunning {
            "\(identity), \(String(localized: "watch.tasks.running"))"
        } else {
            identity
        }
        return commandState.accessibilityLabel(
            baseLabel
        )
    }

    private var taskSystemImage: String {
        if commandState == .idle, isRunning {
            return "timer"
        }
        return commandState.taskSystemImage
    }

    private var taskStateTint: Color {
        if commandState == .idle, isRunning {
            return .green
        }
        return commandState.tint(default: tint)
    }

    private var taskHintKey: LocalizedStringKey {
        if commandState == .idle, isRunning {
            return "watch.tasks.runningHint"
        }
        return commandState.taskHintKey
    }
}
