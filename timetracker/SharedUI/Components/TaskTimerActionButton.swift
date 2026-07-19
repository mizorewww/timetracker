import SwiftUI

enum TaskTimerActionLabelStyle {
    case iconOnly
    case titleAndIcon
}

struct TaskTimerActionButton: View {
    let taskTitle: String
    let taskColor: Color
    let activeSegment: TimeSegment?
    let command: TimerPickerSelectionCommand
    let labelStyle: TaskTimerActionLabelStyle
    let action: () -> Void
    let accessibilityIdentifier: String

    private var usesIconOnly: Bool {
        labelStyle == .iconOnly
    }

    private var actionTitle: String {
        activeSegment == nil
            ? command.actionTitle
            : AppStrings.localized("timer.action.stop")
    }

    private var actionSystemImage: String {
        activeSegment == nil ? command.systemImage : "stop.fill"
    }

    var body: some View {
        Button(role: activeSegment == nil ? nil : .destructive, action: action) {
            actionLabel
        }
        .controlSize(platformControlSize)
        .buttonStyle(.bordered)
        .buttonBorderShape(usesIconOnly ? .circle : .capsule)
        .tint(activeSegment == nil ? taskColor : .red)
        .frame(minWidth: usesIconOnly ? minimumControlHeight : nil)
        .frame(minHeight: minimumControlHeight)
        .contentShape(Rectangle())
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
        .help(accessibilityLabel)
    }

    @ViewBuilder
    private var actionLabel: some View {
        if usesIconOnly {
            Image(systemName: actionSystemImage)
                .font(.callout.weight(.semibold))
                .frame(
                    width: minimumLabelDimension,
                    height: minimumLabelDimension,
                    alignment: .center
                )
        } else {
            Label(actionTitle, systemImage: actionSystemImage)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
                .font(.callout.weight(.semibold))
                .frame(minHeight: minimumLabelDimension)
        }
    }

    private var accessibilityLabel: String {
        activeSegment == nil
            ? command.accessibilityLabel(for: taskTitle)
            : String.localizedStringWithFormat(
                AppStrings.localized("timer.action.stopTaskFormat"),
                taskTitle
            )
    }

    private var accessibilityHint: String {
        activeSegment == nil
            ? command.accessibilityHint
            : AppStrings.localized("timer.task.stopHint")
    }

    private var minimumControlHeight: CGFloat {
        #if os(iOS)
        44
        #else
        28
        #endif
    }

    private var minimumLabelDimension: CGFloat {
        #if os(iOS)
        24
        #else
        16
        #endif
    }

    private var platformControlSize: ControlSize {
        #if os(iOS)
        .large
        #else
        .regular
        #endif
    }
}
