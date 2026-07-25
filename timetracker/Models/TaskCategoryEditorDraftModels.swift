import Foundation

struct TaskCategoryMutationBaseline: Equatable, Sendable {
    let categoryID: UUID
    let clientMutationID: UUID

    init(category: TaskCategory) {
        categoryID = category.id
        clientMutationID = category.clientMutationID
    }
}

struct TaskCategoryEditorDraft: Identifiable, Equatable {
    let id = UUID()
    let baseline: TaskCategoryMutationBaseline?
    var categoryID: UUID?
    var title: String
    var colorHex: String
    var iconName: String
    var includesInForecast: Bool

    init() {
        baseline = nil
        categoryID = nil
        title = ""
        colorHex = "1677FF"
        iconName = "square.grid.2x2"
        includesInForecast = true
    }

    init(category: TaskCategory) {
        baseline = TaskCategoryMutationBaseline(category: category)
        categoryID = category.id
        title = category.title
        colorHex = category.colorHex ?? "1677FF"
        iconName = category.iconName ?? "square.grid.2x2"
        includesInForecast = category.includesInForecast
    }
}
