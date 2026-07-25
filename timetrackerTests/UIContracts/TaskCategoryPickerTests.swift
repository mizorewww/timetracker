import Foundation
import Testing
@testable import timetracker

@Suite(.serialized)
struct TaskCategoryPickerTests {
    @Test @MainActor
    func inboxContextOwnsCategorySpecificCopyAndStableIdentifiers() {
        let context = TaskCategoryPickerSelectionContext.inboxTaskDestination

        #expect(
            context.accessibilityIdentifier ==
                "inbox.categoryTask.categoryPicker"
        )
        #expect(
            context.navigationTitle ==
                AppStrings.localized("inbox.route.categoryTask.title")
        )
        #expect(context.selectionHint.isEmpty == false)
        #expect(context.emptyStateTitle.isEmpty == false)
        #expect(context.emptyStateDescription.isEmpty == false)
    }

}
