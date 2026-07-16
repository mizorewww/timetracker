import Foundation

nonisolated struct TaskIdentityText: Equatable, Sendable {
    let primary: String
    let secondary: String?
}

nonisolated struct TaskVisualPresentation: Equatable, Sendable {
    static let defaultSymbolName = ChecklistVisualSanitizer.defaultIcon
    static let defaultColorHex = ChecklistVisualSanitizer.defaultColor

    let symbolName: String
    let colorHex: String

    init(iconName: String?, colorHex: String?) {
        symbolName = ChecklistVisualSanitizer.sanitizedIcon(iconName)
        self.colorHex = ChecklistVisualSanitizer.sanitizedColor(colorHex)
    }
}

nonisolated struct TaskIdentityPresentation: Equatable, Sendable {
    enum Context: Equatable, Sendable {
        /// The surrounding tree already communicates ancestry.
        case hierarchical
        /// A standalone row or tile needs a separate parent breadcrumb.
        case standard
        /// A single text line must carry the complete identity.
        case compact
    }

    let id: UUID
    let title: String
    let parentPath: String?
    let fullPath: String
    let visual: TaskVisualPresentation

    init(
        id: UUID,
        title: String,
        parentPath: String?,
        fullPath: String,
        visual: TaskVisualPresentation
    ) {
        self.id = id
        self.title = title
        self.parentPath = parentPath.flatMap { $0.isEmpty ? nil : $0 }
        self.fullPath = fullPath.isEmpty ? title : fullPath
        self.visual = visual
    }

    func text(for context: Context) -> TaskIdentityText {
        switch context {
        case .hierarchical:
            TaskIdentityText(primary: title, secondary: nil)
        case .standard:
            TaskIdentityText(primary: title, secondary: parentPath)
        case .compact:
            TaskIdentityText(primary: fullPath, secondary: nil)
        }
    }
}

extension TaskTreeIndexes {
    func taskIdentityPresentation(for taskID: UUID) -> TaskIdentityPresentation? {
        guard let task = taskByID[taskID] else { return nil }
        return TaskIdentityPresentation(
            id: task.id,
            title: task.title,
            parentPath: taskParentPathByID[taskID],
            fullPath: taskPathByID[taskID] ?? task.title,
            visual: TaskVisualPresentation(
                iconName: task.iconName,
                colorHex: task.colorHex
            )
        )
    }
}
