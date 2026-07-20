import SwiftUI

#if os(iOS)
import UIKit
#endif

struct TaskDetailIdentityRow: View {
    let store: TimeTrackerStore
    let task: TaskNode
    @Binding var draft: TaskEditorDraft
    let validation: TaskEditorValidation
    let focusedTextField: FocusState<TaskEditorTextField?>.Binding
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
            TaskIcon(
                visual: TaskVisualPresentation(
                    iconName: draft.iconName,
                    colorHex: draft.colorHex
                ),
                size: 44
            )
            identityText
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .layoutPriority(1)
    }

    private var identityText: some View {
        VStack(alignment: .leading, spacing: 5) {
            TextField(
                AppStrings.localized("editor.task.name"),
                text: $draft.title
            )
                .font(.headline)
                .textFieldStyle(.roundedBorder)
                .focused(focusedTextField, equals: .title)
                .contentShape(Rectangle())
                .foregroundStyle(.primary)
                .submitLabel(.done)
                .onSubmit {
                    focusedTextField.wrappedValue = nil
                }
                .accessibilityHint(validation.titleError?.localizedDescription ?? "")
                .accessibilityIdentifier("task.editor.title.field")

            Text(parentPath)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 2)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("task.detail.identity")

            if let titleError = validation.titleError {
                TaskEditorInlineValidationMessage(
                    error: titleError,
                    accessibilityIdentifier: "task.editor.title.error"
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var parentPath: String {
        guard let parentID = draft.parentID,
              let parent = store.task(for: parentID) else {
            return AppStrings.localized("task.root")
        }
        return store.taskIdentityPresentation(for: parent).fullPath
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
