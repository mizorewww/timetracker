import Foundation
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
    func createTaskRejectsUndeclaredTopLevelKey() throws {
        var overlay = emptyOverlay()
        let result = try executeCreateTask(
            quantityGoal: "null",
            extraField: #","priority":1"#,
            overlay: &overlay
        )

        #expect(result.contains(#""ok":false"#))
        #expect(overlay.snapshot.tasks.isEmpty)
    }

    @Test
    func createTaskRejectsNestedGoalWithUndeclaredKey() throws {
        var overlay = emptyOverlay()
        let result = try executeCreateTask(
            quantityGoal: #"{"targetAmount":3,"unitLabel":"pages","bonus":true}"#,
            overlay: &overlay
        )

        #expect(result.contains(#""ok":false"#))
        #expect(overlay.snapshot.tasks.isEmpty)
    }

    private func emptyOverlay() -> AITaskWorkspaceOverlay {
        AITaskWorkspaceOverlay(
            snapshot: AITaskWorkspaceSnapshot(categories: [], tasks: [], checklistItems: [])
        )
    }

    private func executeCreateTask(
        quantityGoal: String,
        extraField: String = "",
        overlay: inout AITaskWorkspaceOverlay
    ) throws -> String {
        let iconName = try #require(SymbolCatalog.symbolNameSet.first)
        let colorHex = try #require(TaskColorPalette.hexValues.first)
        let arguments = """
        {"title":"Read","parentID":null,"categoryID":null,"notes":"",\
        "estimatedMinutes":null,"dueAt":null,"iconName":"\(iconName)",\
        "colorHex":"\(colorHex)","quantityGoal":\(quantityGoal),\
        "dailyRecurrence":null\(extraField)}
        """
        return try LLMTaskWorkspacePlanningService.execute(
            OpenAIChatToolCall(
                id: "call-1",
                type: "function",
                function: .init(name: AITaskWorkspaceToolName.createTask.rawValue, arguments: arguments)
            ),
            overlay: &overlay,
            makeID: { UUID() }
        )
    }
}
