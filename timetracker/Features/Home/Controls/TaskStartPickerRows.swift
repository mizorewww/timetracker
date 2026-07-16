import SwiftUI

struct TaskStartPickerItem: Identifiable {
    let task: TaskNode
    let path: String
    let activeSegment: TimeSegment?
    let command: TimerPickerSelectionCommand

    var id: UUID { task.id }
}

struct TaskStartPickerActionRow: View {
    let task: TaskNode
    let path: String
    let command: TimerPickerSelectionCommand
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    identity
                    actionLabel
                }
            } else {
                HStack(spacing: 12) {
                    identity
                    Spacer(minLength: 8)
                    actionLabel
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var identity: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .foregroundStyle(.primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
        }
    }

    private var actionLabel: some View {
        Label(command.actionTitle, systemImage: command.systemImage)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.tint)
    }
}

struct TaskStartPickerRunningRow: View {
    let task: TaskNode
    let path: String
    let onStop: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    runningStatus
                    stopButton
                }
            } else {
                HStack(spacing: 12) {
                    runningStatus
                    Spacer(minLength: 8)
                    stopButton
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
    }

    private var runningStatus: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    identity
                    RunningStatusBadge()
                }
            } else {
                HStack(spacing: 12) {
                    identity
                    Spacer(minLength: 8)
                    RunningStatusBadge()
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            String(format: AppStrings.localized("timer.picker.runningTaskFormat"), task.title)
        )
        .accessibilityValue(path)
        .accessibilityHint(AppStrings.localized("timer.picker.runningHint"))
    }

    private var identity: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .foregroundStyle(.primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .fixedSize(horizontal: false, vertical: dynamicTypeSize.isAccessibilitySize)
            }
        }
    }

    private var stopButton: some View {
        Button(action: onStop) {
            Label(AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
                .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityLabel(
            String(format: AppStrings.localized("timer.action.stopTaskFormat"), task.title)
        )
        .accessibilityHint(AppStrings.localized("timer.task.stopHint"))
        .accessibilityIdentifier("timer.taskPicker.stop.\(task.id.uuidString)")
    }
}

extension TimerPickerMode {
    var title: String {
        switch self {
        case .start:
            AppStrings.startTimer
        case .startAnother:
            AppStrings.localized("home.startAnotherTimer")
        case .switchTimer:
            AppStrings.localized("home.switchTimer")
        }
    }

    var systemImage: String {
        switch self {
        case .start:
            "play.fill"
        case .startAnother:
            "plus"
        case .switchTimer:
            "arrow.left.arrow.right"
        }
    }

    var sectionHeader: LocalizedStringKey {
        switch self {
        case .start, .startAnother:
            .app("timer.picker.availableHeader")
        case .switchTimer:
            .app("timer.picker.switchHeader")
        }
    }

    var footer: LocalizedStringKey {
        switch self {
        case .start:
            .app("timer.picker.startFooter")
        case .startAnother:
            .app("timer.picker.parallelFooter")
        case .switchTimer:
            .app("timer.picker.switchFooter")
        }
    }
}

extension TimerPickerSelectionCommand {
    var actionTitle: String {
        switch self {
        case .alreadyRunning:
            AppStrings.running
        case .start:
            AppStrings.localized("timer.picker.action.start")
        case .switchTimer:
            AppStrings.localized("timer.picker.action.switch")
        }
    }

    var systemImage: String {
        switch self {
        case .alreadyRunning:
            "checkmark"
        case .start:
            "play.fill"
        case .switchTimer:
            "arrow.left.arrow.right"
        }
    }

    var accessibilityHint: String {
        switch self {
        case .alreadyRunning:
            AppStrings.localized("timer.picker.runningHint")
        case .start:
            AppStrings.localized("timer.task.startHint")
        case .switchTimer:
            AppStrings.localized("timer.task.switchHint")
        }
    }

    func accessibilityLabel(for taskTitle: String) -> String {
        let key = switch self {
        case .alreadyRunning:
            "timer.picker.runningTaskFormat"
        case .start:
            "timer.picker.startTaskFormat"
        case .switchTimer:
            "timer.picker.switchTaskFormat"
        }
        return String(format: AppStrings.localized(key), taskTitle)
    }
}
