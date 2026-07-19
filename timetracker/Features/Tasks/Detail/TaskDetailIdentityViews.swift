import SwiftUI

#if os(iOS)
import UIKit
#endif

struct TaskDetailIdentityRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityContent
            } else {
                standardContent
            }
        }
        .padding(.vertical, 4)
    }

    private var standardContent: some View {
        HStack(alignment: .center, spacing: 14) {
            identitySummary
            timerAction
        }
    }

    private var accessibilityContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            identitySummary

            if showsTimerAction {
                HStack {
                    Spacer(minLength: 0)
                    timerAction
                }
            }
        }
    }

    private var identitySummary: some View {
        HStack(alignment: .top, spacing: 14) {
            TaskIcon(task: task, size: 44)
            identityText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("task.detail.identity")
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(task.title)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)

            Text(store.parentPath(for: task) ?? AppStrings.localized("task.root"))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var timerAction: some View {
        if showsTimerAction {
            TaskTimerActionButton(
                taskTitle: task.title,
                taskColor: Color(hex: task.colorHex) ?? .blue,
                activeSegment: activeSegment,
                command: store.timerPickerSelectionCommand(for: task),
                labelStyle: timerActionLabelStyle,
                action: performTimerAction,
                accessibilityIdentifier: "task.detail.timer"
            )
        }
    }

    private var activeSegment: TimeSegment? {
        store.activeSegment(for: task.id)
    }

    private var showsTimerAction: Bool {
        activeSegment != nil || store.isTaskAvailableForTracking(task)
    }

    private var timerActionLabelStyle: TaskTimerActionLabelStyle {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone ? .iconOnly : .titleAndIcon
        #else
        .titleAndIcon
        #endif
    }

    private func performTimerAction() {
        if let activeSegment {
            store.stop(segment: activeSegment)
        } else {
            store.performTimerPickerSelection(task)
        }
    }
}
