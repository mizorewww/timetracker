import SwiftUI

struct WatchTaskShortcutRow: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    let task: WatchRecentTaskSnapshot
    let commandState: WatchRowCommandState
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
        .accessibilityHint(Text(commandState.taskHintKey))
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
        Image(systemName: commandState.taskSystemImage)
            .font(.caption.weight(.semibold))
            .foregroundStyle(commandState.tint(default: tint))
            .accessibilityHidden(true)
    }

    private var accessibilityLabel: String {
        commandState.accessibilityLabel(
            task.path.isEmpty ? task.title : "\(task.title), \(task.path)"
        )
    }
}
