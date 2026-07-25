import SwiftUI

enum TaskTimerActionLabelStyle {
    case iconOnly
    case titleAndIcon
}

enum TaskTimerActionKind: CaseIterable, Equatable {
    case start
    case switchTimer
    case alreadyRunning
    case stop

    var compactSystemImage: String {
        switch self {
        case .start:
            "play.circle.fill"
        case .switchTimer:
            "arrow.left.arrow.right.circle.fill"
        case .alreadyRunning:
            "checkmark.circle.fill"
        case .stop:
            "stop.circle.fill"
        }
    }

    var labeledSystemImage: String {
        switch self {
        case .start:
            "play.fill"
        case .switchTimer:
            "arrow.left.arrow.right"
        case .alreadyRunning:
            "checkmark"
        case .stop:
            "stop.fill"
        }
    }
}

enum TaskPickerIndicatorMetrics {
    static var actionControlDimension: CGFloat {
        #if os(iOS)
        54
        #else
        28
        #endif
    }

    static var passiveSlotDimension: CGFloat {
        #if os(iOS)
        20
        #else
        16
        #endif
    }
}

private struct TaskPickerIconButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(opacity(isPressed: configuration.isPressed))
            .animation(
                .easeOut(duration: 0.12),
                value: configuration.isPressed
            )
    }

    private func opacity(isPressed: Bool) -> Double {
        guard isEnabled else { return 0.45 }
        return isPressed ? 0.55 : 1
    }
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

    private var actionKind: TaskTimerActionKind {
        guard activeSegment == nil else { return .stop }
        switch command {
        case .start:
            return .start
        case .switchTimer:
            return .switchTimer
        case .alreadyRunning:
            return .alreadyRunning
        }
    }

    var body: some View {
        if usesIconOnly {
            configuredButton {
                Image(systemName: actionKind.compactSystemImage)
                    .symbolRenderingMode(.monochrome)
                    .font(.title2.weight(.semibold))
                    .imageScale(.large)
                    .foregroundStyle(actionColor)
                    .frame(
                        width: TaskPickerIndicatorMetrics.actionControlDimension,
                        height: TaskPickerIndicatorMetrics.actionControlDimension
                    )
                    .contentShape(Circle())
                    .accessibilityHidden(true)
            }
            .buttonStyle(TaskPickerIconButtonStyle())
        } else {
            configuredButton {
                Label(actionTitle, systemImage: actionKind.labeledSystemImage)
                    .labelStyle(.titleAndIcon)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(actionColor)
                    .frame(minHeight: minimumLabelDimension)
            }
            .controlSize(platformControlSize)
            .buttonStyle(.bordered)
            .buttonBorderShape(.capsule)
            .tint(actionColor)
            .frame(minHeight: minimumControlHeight)
        }
    }

    private func configuredButton<Label: View>(
        @ViewBuilder label: () -> Label
    ) -> some View {
        Button(
            role: activeSegment == nil ? nil : .destructive,
            action: action,
            label: label
        )
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(accessibilityHint)
        .accessibilityIdentifier(accessibilityIdentifier)
        .help(accessibilityLabel)
    }

    private var actionColor: Color {
        guard activeSegment == nil else { return .red }
        return usesIconOnly ? .accentColor : taskColor
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
        26
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
