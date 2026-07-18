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

            selectionButton(item, sectionKind: sectionKind)
        }
        .padding(
            .leading,
            sectionKind == .hierarchy
                ? CGFloat(min(item.depth, 6)) * 12
                : 0
        )
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
                    .foregroundStyle(.secondary)
                    .frame(width: 14, height: 18)
            }
            .buttonStyle(.plain)
            .frame(width: disclosureTargetSize, height: disclosureTargetSize)
            .contentShape(Rectangle())
            .accessibilityLabel(disclosureLabel(for: item))
            .accessibilityIdentifier(
                "taskHierarchy.disclosure.\(item.id.uuidString)"
            )
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
        .disabled(item.isAvailable == false)
        .accessibilityLabel(accessibilityLabel(for: item))
        .accessibilityValue(accessibilityValue(for: item))
        .accessibilityHint(accessibilityHint(for: item))
        .accessibilityAddTraits(isSelected(item) ? .isSelected : [])
        .accessibilityIdentifier(selectionIdentifier(for: item))
    }

    @ViewBuilder
    func selectionLabel(
        _ item: TaskHierarchyProjection.Item,
        sectionKind: TaskHierarchyProjection.Section.Kind
    ) -> some View {
        switch mode {
        case .timer:
            VStack(alignment: .leading, spacing: 8) {
                TaskIdentityRow(
                    presentation: item.identity,
                    context: identityContext(for: sectionKind)
                )
                Label(
                    item.timerCommand.actionTitle,
                    systemImage: item.timerCommand.systemImage
                )
                .font(.callout.weight(.semibold))
                .foregroundStyle(.tint)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        case .singleSelection:
            HStack(alignment: .top, spacing: 8) {
                TaskIdentityRow(
                    presentation: item.identity,
                    context: identityContext(for: sectionKind)
                )
                if isSelected(item) {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.tint)
                        .frame(minWidth: 28, minHeight: 28)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
    }

    func runningRow(_ item: TaskHierarchyProjection.Item) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            TaskIdentityRow(
                presentation: item.identity,
                context: .standard
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(
                String(
                    format: AppStrings.localized("timer.picker.runningTaskFormat"),
                    item.identity.title
                )
            )
            .accessibilityValue(item.identity.fullPath)
            .accessibilityHint(AppStrings.localized("timer.picker.runningHint"))

            HStack(spacing: 12) {
                RunningStatusBadge()
                    .accessibilityHidden(true)
                Spacer(minLength: 8)
                stopButton(item)
            }
        }
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier(
            "timer.taskPicker.running.\(item.id.uuidString)"
        )
    }

    func stopButton(_ item: TaskHierarchyProjection.Item) -> some View {
        Button {
            guard let activeSegment = store.activeSegment(for: item.id) else {
                return
            }
            store.stop(segment: activeSegment)
        } label: {
            Label(
                AppStrings.localized("timer.action.stop"),
                systemImage: "stop.fill"
            )
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(Color.red)
            .frame(minHeight: 44)
        }
        .buttonStyle(.bordered)
        .tint(.red)
        .accessibilityLabel(
            String(
                format: AppStrings.localized("timer.action.stopTaskFormat"),
                item.identity.title
            )
        )
        .accessibilityHint(AppStrings.localized("timer.task.stopHint"))
        .accessibilityIdentifier(
            "timer.taskPicker.stop.\(item.id.uuidString)"
        )
    }

    private func identityContext(
        for sectionKind: TaskHierarchyProjection.Section.Kind
    ) -> TaskIdentityPresentation.Context {
        sectionKind == .hierarchy ? .hierarchical : .standard
    }

    private func disclosureLabel(
        for item: TaskHierarchyProjection.Item
    ) -> String {
        let action = item.isExpanded
            ? AppStrings.localized("task.tree.collapse")
            : AppStrings.localized("task.tree.expand")
        return "\(item.identity.title), \(action)"
    }
}
