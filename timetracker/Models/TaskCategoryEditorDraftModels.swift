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
        self.baseline = nil
        self.categoryID = nil
        self.title = ""
        self.colorHex = "1677FF"
        self.iconName = "square.grid.2x2"
        self.includesInForecast = true
    }

    init(category: TaskCategory) {
        self.baseline = TaskCategoryMutationBaseline(category: category)
        self.categoryID = category.id
        self.title = category.title
        self.colorHex = category.colorHex ?? "1677FF"
        self.iconName = category.iconName ?? "square.grid.2x2"
        self.includesInForecast = category.includesInForecast
    }
}
