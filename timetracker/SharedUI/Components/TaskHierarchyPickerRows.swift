import SwiftUI

extension TaskHierarchyPicker {
    func hierarchyRow(
        _ item: TaskHierarchyProjection.Item,
        sectionKind: TaskHierarchyProjection.Section.Kind
    ) -> some View {
        HStack(alignment: .top, spacing: 4) {
            if sectionKind == .hierarchy {
                disclosureControl(item)
            }

            switch mode {
            case .timer:
                timerSelectionRow(item, sectionKind: sectionKind)
            case .singleSelection, .multipleSelection:
                selectionButton(item, sectionKind: sectionKind)
            }
        }
        .padding(.leading, sectionKind == .hierarchy
            ? CGFloat(min(item.depth, 6)) * 12
            : 0)
    }

    @ViewBuilder
    func disclosureControl(_ item: TaskHierarchyProjection.Item) -> some View {
        switch TaskTreeDisclosureSlot(depth: item.depth, hasChildren: item.hasChildren) {
        case .control:
            Button {
                toggleExpansion(item.id)
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .rotationEffect(.degrees(item.isExpanded ? 90 : 0))
                    .animation(
                        reduceMotion ? nil : AppMotion.stateChange,
                        value: item.isExpanded
                    )
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 18)
            }
            .buttonStyle(.plain)
            .frame(width: disclosureTargetSize, height: disclosureTargetSize)
            .contentShape(Rectangle())
            .accessibilityLabel(disclosureLabel(for: item))
            .accessibilityIdentifier("taskHierarchy.disclosure.\(item.id.uuidString)")
        case .reserved:
            Color.clear
                .frame(width: disclosureTargetSize, height: disclosureTargetSize)
                .accessibilityHidden(true)
        case .none:
            EmptyView()
        }
    }

    func selectionButton(
        _ item: TaskHierarchyProjection.Item,
        sectionKind: TaskHierarchyProjection.Section.Kind
    ) -> some View {
        Button {
            select(item)
        } label: {
            selectionLabel(item, sectionKind: sectionKind)
        }
        .buttonStyle(.plain)
        .disabled(isSelectionDisabled(for: item))
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityValue(accessibilityValue(for: item))
        .accessibilityHint(accessibilityHint(for: item))
        .accessibilityAddTraits(isSelected(item) ? .isSelected : [])
        .accessibilityIdentifier(selectionIdentifier(for: item))
    }

    func selectionLabel(
        _ item: TaskHierarchyProjection.Item,
        sectionKind: TaskHierarchyProjection.Section.Kind
    ) -> some View {
        TaskSummaryRow(
            presentation: item.identity,
            context: identityContext(for: sectionKind),
            metadata: TaskSummaryRowMetadata(
                checklistProgress: item.checklistProgress,
                workedSeconds: item.workedSeconds,
                isRunning: item.isRunning,
                accessory: isSelected(item) ? .selected : .none
            )
        )
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    func timerSelectionRow(
        _ item: TaskHierarchyProjection.Item,
        sectionKind: TaskHierarchyProjection.Section.Kind
    ) -> some View {
        HStack(alignment: .top, spacing: 12) {
            timerTaskSummary(item, context: identityContext(for: sectionKind))

            TaskTimerActionButton(
                taskTitle: item.identity.title,
                taskColor: Color(hex: item.identity.visual.colorHex) ?? .blue,
                activeSegment: nil,
                command: item.timerCommand,
                labelStyle: pickerActionLabelStyle,
                action: { select(item) },
                accessibilityIdentifier: selectionIdentifier(for: item)
            )
            .disabled(item.isAvailable == false)
            .accessibilityValue(accessibilityValue(for: item))
            .accessibilityHint(accessibilityHint(for: item))
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    func runningRow(_ item: TaskHierarchyProjection.Item) -> some View {
        HStack(alignment: .top, spacing: 12) {
            timerTaskSummary(item, context: .standard)

            stopButton(item)
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    func stopButton(_ item: TaskHierarchyProjection.Item) -> some View {
        if let activeSegment = store.activeSegment(for: item.id) {
            TaskTimerActionButton(
                taskTitle: item.identity.title,
                taskColor: Color(hex: item.identity.visual.colorHex) ?? .blue,
                activeSegment: activeSegment,
                command: .alreadyRunning,
                labelStyle: pickerActionLabelStyle,
                action: { store.stop(segment: activeSegment) },
                accessibilityIdentifier: "timer.taskPicker.stop.\(item.id.uuidString)"
            )
            .accessibilityValue(accessibilityValue(for: item))
        }
    }

    private func timerTaskSummary(
        _ item: TaskHierarchyProjection.Item,
        context: TaskIdentityPresentation.Context
    ) -> some View {
        TaskSummaryRow(
            presentation: item.identity,
            context: context,
            metadata: TaskSummaryRowMetadata(
                checklistProgress: item.checklistProgress,
                workedSeconds: item.workedSeconds
            )
        )
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.identity.title)
        .accessibilityValue(accessibilityValue(for: item))
        .accessibilityIdentifier("timer.taskPicker.summary.\(item.id.uuidString)")
    }

    private var pickerActionLabelStyle: TaskTimerActionLabelStyle {
        .iconOnly
    }

    private func identityContext(
        for sectionKind: TaskHierarchyProjection.Section.Kind
    ) -> TaskIdentityPresentation.Context {
        sectionKind == .hierarchy ? .hierarchical : .standard
    }

    private func disclosureLabel(for item: TaskHierarchyProjection.Item) -> String {
        let action = item.isExpanded
            ? AppStrings.localized("task.tree.collapse")
            : AppStrings.localized("task.tree.expand")
        return "\(item.identity.title), \(action)"
    }
}
