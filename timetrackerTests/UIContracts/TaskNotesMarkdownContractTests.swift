import Foundation
import Testing

@Suite
struct TaskNotesMarkdownContractTests {
    @Test
    func taskWorkspaceRendersMarkdownWhileTheEditorKeepsPortableSource() throws {
        let detail = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift"
        )
        let recovery = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailAvailabilityViews.swift"
        )
        let preview = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskNotesMarkdownPreview.swift"
        )
        let components = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskEditorComponents.swift"
        )
        let editor = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskNotesEditorSection.swift"
        )

        #expect(detail.contains(
            "notesInteractionStyle: .expandablePreview"
        ))
        #expect(recovery.contains(
            "notesInteractionStyle: .expandablePreview"
        ))
        #expect(
            components.components(
                separatedBy: """
                notesInteractionStyle: TaskNotesInteractionStyle = .editor
                """
            ).count == 3
        )
        for source in [detail, recovery, components, editor] {
            #expect(source.contains("notesStartInPreview") == false)
        }
        #expect(preview.contains("import MarkdownView"))
        #expect(preview.contains("view.linkHandler ="))
        #expect(preview.contains("openURL(url)"))
        #expect(preview.contains("view.boundingSize(for: width)"))
        #expect(preview.contains("MarkdownTheme()"))
        #expect(editor.contains("TextEditor(text: $notes)"))
        #expect(editor.contains("TaskNotesMarkdownPreview(markdown: notes)"))
        #expect(editor.contains("enum TaskNotesInteractionStyle"))
        #expect(editor.contains("case expandablePreview"))
        #expect(editor.contains("task.editor.notes.mode"))
        #expect(editor.contains("task.editor.notes.edit"))
        #expect(editor.contains("task.editor.notes.done"))
        #expect(editor.contains("task.editor.notes.empty"))
        #expect(editor.contains("mode = .source"))
        #expect(editor.contains("focusedTextField.wrappedValue = .notes"))
        #expect(editor.contains("task.notes.preview"))

        let finishStart = try #require(
            editor.range(of: "private func finishEditing()")
        )
        let finishSource = editor[finishStart.lowerBound...]
        let focusClear = try #require(
            finishSource.range(of: "focusedTextField.wrappedValue = nil")
        )
        let previewTransition = try #require(
            finishSource.range(of: "mode = .preview")
        )
        #expect(focusClear.lowerBound < previewTransition.lowerBound)
    }

    @Test
    func markdownViewDependencyIsExactlyPinnedToTheReviewedRevision() throws {
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")
        let resolved = try sourceText(
            "timetracker.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )

        #expect(project.contains(
            "repositoryURL = \"https://github.com/Lakr233/MarkdownView\";"
        ))
        #expect(project.contains("kind = exactVersion;"))
        #expect(project.contains("version = 4.1.7;"))
        #expect(resolved.contains("\"identity\" : \"markdownview\""))
        #expect(resolved.contains(
            "\"revision\" : \"84381f59cc52606ffc198fb2fdac8e6a44abe528\""
        ))
        #expect(resolved.contains("\"version\" : \"4.1.7\""))
    }
}
