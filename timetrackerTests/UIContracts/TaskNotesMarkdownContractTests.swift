import Testing

@Suite
struct TaskNotesMarkdownContractTests {
    @Test
    func taskWorkspaceRendersMarkdownWhileTheEditorKeepsPortableSource() throws {
        let detail = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskDetailContentView.swift"
        )
        let preview = try sourceText(
            "timetracker/Features/Tasks/Detail/TaskNotesMarkdownPreview.swift"
        )
        let editor = try sourceText(
            "timetracker/Features/Tasks/Editor/TaskNotesEditorSection.swift"
        )

        #expect(detail.contains("TaskNotesMarkdownPreview(markdown: notes)"))
        #expect(preview.contains("import MarkdownView"))
        #expect(preview.contains("view.linkHandler ="))
        #expect(preview.contains("openURL(url)"))
        #expect(preview.contains("view.boundingSize(for: width)"))
        #expect(preview.contains("MarkdownTheme()"))
        #expect(editor.contains("TextEditor(text: $notes)"))
        #expect(editor.contains("MarkdownView") == false)
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
