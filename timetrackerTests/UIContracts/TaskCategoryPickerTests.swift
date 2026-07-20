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

    @Test
    func sharedCategoryPickerUsesNativeSearchAndMinimumTargetSizing() throws {
        let source = try sourceText(
            "timetracker/SharedUI/Components/TaskCategoryPicker.swift"
        )
        let sheet = try sourceText(
            "timetracker/SharedUI/Components/TaskCategoryPickerSheet.swift"
        )

        #expect(source.contains(".searchable("))
        #expect(source.contains("localizedStandardContains("))
        #expect(source.contains("AppLayout.minimumInteractiveTarget"))
        #expect(source.contains("context.accessibilityIdentifier"))
        #expect(source.contains(".accessibilityAddTraits("))
        #expect(sheet.contains("store.taskCategories.map"))
        #expect(sheet.contains(".presentationDetents("))
        #expect(sheet.contains(".presentationDragIndicator(.visible)"))
    }
}
