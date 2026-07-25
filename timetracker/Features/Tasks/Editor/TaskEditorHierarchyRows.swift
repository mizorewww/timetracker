import SwiftUI

struct TaskParentPickerOption: Identifiable, Equatable {
    let id: UUID
    let title: String
    let isAvailable: Bool
}

struct TaskInheritedCategoryHint: Equatable {
    let title: String
    let iconName: String
    let colorHex: String?
}

struct TaskParentPickerRow: View {
    @Binding var selection: UUID?
    let options: [TaskParentPickerOption]
    let changeBlocker: TaskParentChangeBlocker?

    var body: some View {
        Picker(AppStrings.localized("editor.task.parent"), selection: $selection) {
            Text(.app("editor.task.rootLevel")).tag(UUID?.none)
            ForEach(options) { option in
                Text(title(for: option))
                    .tag(Optional(option.id))
                    .disabled(option.isAvailable == false && selection != option.id)
            }
            if let missingCurrentParentID {
                Text(.app("task.parent.currentMissing"))
                    .tag(Optional(missingCurrentParentID))
            }
        }
        .disabled(changeBlocker != nil)
        .accessibilityIdentifier("task.editor.parent")
        .accessibilityValue(accessibilitySelectionValue)
    }

    private var missingCurrentParentID: UUID? {
        guard let selection,
              options.contains(where: { $0.id == selection }) == false
        else {
            return nil
        }
        return selection
    }

    private var accessibilitySelectionValue: String {
        guard let selection else {
            return AppStrings.localized("editor.task.rootLevel")
        }
        guard let option = options.first(where: { $0.id == selection }) else {
            return AppStrings.localized("task.parent.currentMissing")
        }
        return title(for: option)
    }

    private func title(for option: TaskParentPickerOption) -> String {
        guard option.isAvailable == false else { return option.title }
        return String.localizedStringWithFormat(
            AppStrings.localized(
                selection == option.id
                    ? "task.parent.currentUnavailableFormat"
                    : "task.parent.unavailableFormat"
            ),
            option.title
        )
    }
}

struct TaskCategoryPickerRow: View {
    @Binding var selection: UUID?
    let options: [TaskCategoryPickerOption]

    var body: some View {
        Picker(AppStrings.localized("taskCategory.title"), selection: $selection) {
            Text(.app("taskCategory.none")).tag(UUID?.none)
            ForEach(options) { option in
                Label(option.title, systemImage: option.iconName)
                    .tag(Optional(option.id))
            }
        }
        .accessibilityIdentifier("task.editor.category")
        .accessibilityValue(accessibilitySelectionValue)
    }

    private var accessibilitySelectionValue: String {
        guard let selection,
              let option = options.first(where: { $0.id == selection })
        else {
            return AppStrings.localized("taskCategory.none")
        }
        return option.title
    }
}

struct TaskReadOnlyCategoryRow: View {
    let category: TaskInheritedCategoryHint

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(AppStrings.localized("taskCategory.title")) {
                Label {
                    Text(category.title)
                        .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: category.iconName)
                        .foregroundStyle(
                            Color(hex: category.colorHex) ?? .secondary
                        )
                }
            }
            .labeledContentStyle(TaskReadOnlyCategoryLabeledContentStyle())
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(AppStrings.localized("taskCategory.title"))
            .accessibilityValue(category.title)
            .accessibilityIdentifier("task.editor.category.readOnly")

            Label(
                AppStrings.localized("task.healthSyncOnly.categoryLocked"),
                systemImage: "lock.fill"
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .accessibilityLabel(
                AppStrings.localized("task.healthSyncOnly.categoryLocked")
            )
            .accessibilityIdentifier("task.editor.category.readOnly.reason")
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct TaskReadOnlyCategoryLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            configuration.label
            Spacer(minLength: 12)
            configuration.content
        }
    }
}

struct TaskHierarchyEditorHints: View {
    let inheritedCategory: TaskInheritedCategoryHint?
    let parentChangeBlocker: TaskParentChangeBlocker?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let inheritedCategory {
                Label {
                    Text(
                        String(
                            format: AppStrings.localized("taskCategory.inherited"),
                            inheritedCategory.title
                        )
                    )
                    .foregroundStyle(.secondary)
                } icon: {
                    Image(systemName: inheritedCategory.iconName)
                        .foregroundStyle(Color(hex: inheritedCategory.colorHex) ?? .secondary)
                }
            }
            if let parentSelectionLockMessageKey {
                Label(
                    AppStrings.localized(parentSelectionLockMessageKey),
                    systemImage: "lock.fill"
                )
                .foregroundStyle(.secondary)
            }
        }
        .font(.caption)
    }

    private var parentSelectionLockMessageKey: String? {
        switch parentChangeBlocker {
        case .archived:
            "task.parent.archivedLocked"
        case .unavailable:
            "task.parent.unavailableLocked"
        case nil:
            nil
        }
    }
}
