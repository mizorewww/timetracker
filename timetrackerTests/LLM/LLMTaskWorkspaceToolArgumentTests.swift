import Foundation
import OpenAI
import Testing
@testable import timetracker

@MainActor
struct LLMTaskWorkspaceToolArgumentTests {
    @Test
    func createTaskAcceptsExactSchemaIncludingNestedProgress() throws {
        var overlay = emptyOverlay()
        let result = try executeCreateTask(
            quantityGoal: #"{"targetAmount":3,"unitLabel":"pages"}"#,
            overlay: &overlay
        )

        #expect(result.contains(#""ok":true"#))
        let task = try #require(overlay.snapshot.tasks.first)
        #expect(task.quantityGoal == TaskQuantityGoalDraft(targetAmount: 3, unitLabel: "pages"))
    }

    @Test
    func createTaskTreatsOmittedOptionalKeysAsNullAndIgnoresUnknownKeys() throws {
        var overlay = emptyOverlay()
        let iconName = try #require(SymbolCatalog.symbolNameSet.first)
        let colorHex = try #require(TaskColorPalette.hexValues.first)
        let result = try execute(
            .createTask,
            arguments: """
            {"title":"Read","notes":"","iconName":"\(iconName)",\
            "colorHex":"\(colorHex)","priority":1}
            """,
            overlay: &overlay
        )

        #expect(result.contains(#""ok":true"#))
        let task = try #require(overlay.snapshot.tasks.first)
        #expect(task.parentID == nil)
        #expect(task.quantityGoal == nil)
        #expect(task.dueAt == nil)
    }

    @Test
    func invalidArgumentsReturnAFailureResultWithoutChanges() throws {
        var overlay = emptyOverlay()
        let missingTitle = try executeCreateTask(
            quantityGoal: "null",
            title: nil,
            overlay: &overlay
        )
        let incompleteGoal = try executeCreateTask(
            quantityGoal: #"{"targetAmount":3}"#,
            overlay: &overlay
        )
        let offCatalogIcon = try execute(
            .createCategory,
            arguments: """
            {"title":"Work","iconName":"not.a.symbol","colorHex":"000000",\
            "includesInForecast":true}
            """,
            overlay: &overlay
        )

        for result in [missingTitle, incompleteGoal, offCatalogIcon] {
            #expect(result.contains(#""ok":false"#))
        }
        #expect(overlay.snapshot.tasks.isEmpty)
        #expect(overlay.snapshot.categories.isEmpty)
        #expect(overlay.operations.isEmpty)
    }

    @Test
    func overlayRejectsOffCatalogVisuals() {
        var overlay = emptyOverlay()

        #expect(throws: AITaskWorkspaceOverlayError.invalidVisual) {
            try overlay.createCategory(
                id: UUID(),
                title: "Work",
                iconName: "not.a.symbol",
                colorHex: "not-a-color"
            )
        }
        #expect(overlay.operations.isEmpty)
    }

    private func emptyOverlay() -> AITaskWorkspaceOverlay {
        AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(categories: [], tasks: [], checklistItems: [])
        )
    }

    private func executeCreateTask(
        quantityGoal: String,
        title: String? = "Read",
        overlay: inout AITaskWorkspaceOverlay
    ) throws -> String {
        let iconName = try #require(SymbolCatalog.symbolNameSet.first)
        let colorHex = try #require(TaskColorPalette.hexValues.first)
        let titleField = title.map { #""title":"\#($0)","# } ?? ""
        return try execute(
            .createTask,
            arguments: """
            {\(titleField)"parentID":null,"categoryID":null,"notes":"",\
            "estimatedMinutes":null,"dueAt":null,"iconName":"\(iconName)",\
            "colorHex":"\(colorHex)","quantityGoal":\(quantityGoal),\
            "dailyRecurrence":null}
            """,
            overlay: &overlay
        )
    }

    private func execute(
        _ tool: AITaskWorkspaceToolName,
        arguments: String,
        overlay: inout AITaskWorkspaceOverlay
    ) throws -> String {
        try LLMTaskWorkspacePlanningService.execute(
            .init(
                id: "call-1",
                function: .init(arguments: arguments, name: tool.rawValue)
            ),
            overlay: &overlay,
            makeID: { UUID() }
        )
    }
}
