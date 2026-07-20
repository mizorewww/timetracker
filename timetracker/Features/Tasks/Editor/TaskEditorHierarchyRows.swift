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
            Text(.app("editor.task.rootLevel")).tag(Optional<UUID>.none)
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
    }

    private var missingCurrentParentID: UUID? {
        guard let selection,
              options.contains(where: { $0.id == selection }) == false else {
            return nil
        }
        return selection
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
            Text(.app("taskCategory.none")).tag(Optional<UUID>.none)
            ForEach(options) { option in
                Label(option.title, systemImage: option.iconName)
                    .tag(Optional(option.id))
            }
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
        case .deleted:
            "task.parent.deletedLocked"
        case nil:
            nil
        }
    }
}
