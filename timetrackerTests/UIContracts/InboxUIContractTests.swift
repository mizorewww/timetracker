import Foundation
import Testing

@Suite(.serialized)
struct InboxUIContractTests {
    @Test
    func inboxUsesOwnDestinationAndSmoothInlineCapture() throws {
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore.swift")
        let contentSource = try appRootSource()
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let inboxSource = try inboxFeatureSource()
        let inboxStoreSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+InboxCommands.swift")
        let taskEditorSource = try taskEditorFeatureSource()
        let schemaSource = try sourceText("timetracker/Models/SchemaModels.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")
        let sharedChecklistSource = try sourceText("timetracker/SharedUI/Components/ChecklistControls.swift")

        #expect(storeSource.contains("case inbox = \"Inbox\""))
        #expect(contentSource.contains("case .inbox:"))
        #expect(contentSource.contains("InboxView(store: store)"))
        #expect(sidebarSource.contains("return TimeTrackerStore.DesktopDestination.allCases.filter { $0 != .settings }"))
        #expect(tasksSource.contains("InboxNavigationRow(count: store.openInboxItems.count)") == false)
        #expect(inboxSource.contains("ScrollView {"))
        #expect(inboxSource.contains("private var inboxCard"))
        #expect(inboxSource.contains("List {"))
        #expect(inboxSource.contains("InboxCaptureRow("))
        #expect(inboxSource.contains("EditableChecklistTextRow("))
        #expect(inboxSource.contains(".onMove(perform: moveInboxItems)"))
        #expect(inboxSource.contains(".swipeActions(edge: .leading"))
        #expect(inboxSource.contains(".swipeActions(edge: .trailing"))
        #expect(inboxSource.contains("EditButton()") == false)
        #expect(inboxSource.contains("toggleSorting()"))
        #expect(inboxSource.contains("ToolbarItem(placement: .topBarTrailing)"))
        #expect(inboxSource.contains(".environment(\\.editMode"))
        #expect(inboxSource.contains("RoundedRectangle(cornerRadius: layout.cardCornerRadius"))
        #expect(inboxSource.contains("InboxLayoutPolicy("))
        #expect(inboxSource.contains("layout.cardHorizontalPadding"))
        #expect(inboxSource.contains("InlineInboxAddRow") == false)
        #expect(inboxSource.contains("showsCompleted") == false)
        #expect(inboxSource.contains("inbox.subtitle"))
        #expect(inboxSource.contains("lightbulb"))
        #expect(inboxSource.contains(".buttonStyle(.plain)"))
        #expect(inboxSource.contains(".buttonStyle(.bordered)") == false)
        #expect(inboxSource.contains(".buttonBorderShape(.circle)") == false)
        #expect(inboxSource.contains("withAnimation(.snappy") == false)
        #expect(inboxSource.contains(".animation(.snappy") == false)
        #expect(inboxSource.contains("frame(width: isCompact ? 54 : 44") == false)
        #expect(inboxSource.contains("Text(AppStrings.localized(\"inbox.suggestion.prefix\"))"))
        #expect(inboxSource.contains("taskTitle: task.title"))
        #expect(inboxSource.contains("let taskTitle: String"))
        #expect(inboxSource.contains("taskPath: store.taskPath(for: task)") == false)
        #expect(inboxSource.contains("Text(taskPath)") == false)
        #expect(inboxSource.contains("return \"tray\""))
        #expect(inboxSource.contains(".navigationTitle(AppStrings.inbox)"))
        #expect(inboxSource.contains(".navigationTitle(isCompact ? \"\" : AppStrings.inbox)") == false)
        #expect(inboxSource.contains(".navigationBarTitleDisplayMode(isCompact ? .large : .inline)"))
        #expect(inboxSource.contains(".toolbar(isCompact ? .hidden : .visible, for: .navigationBar)") == false)
        #expect(inboxSource.contains("let submit: () -> Bool"))
        #expect(inboxStoreSource.contains("suggestInboxItem(item, showsErrors: false)"))
        #expect(inboxStoreSource.contains("func reorderInboxItems(sourceOffsets: IndexSet, destination: Int)"))
        #expect(sharedChecklistSource.contains("ChecklistInputTextNormalizer"))
        #expect(sharedChecklistSource.contains("collapsingNewlines"))
        #expect(taskEditorSource.contains(".submitLabel(.done)"))
        #expect(taskEditorSource.contains("ChecklistInputTextNormalizer.collapsingNewlines"))
        #expect(sharedChecklistSource.contains("struct EditableChecklistTextRow"))
        #expect(sharedChecklistSource.contains(".symbolEffect(.bounce, value: isCompleted)") == false)
        #expect(inboxSource.contains("store.addInboxItem(title: title)"))
        #expect(schemaSource.contains("enum TimeTrackerSchemaV6"))
        #expect(schemaSource.contains("InboxItem.self"))
    }

    @Test
    func inboxSuggestionsAreAutomaticAndExposeOnlyApplyOrDiscardActions() throws {
        let inboxSource = try inboxFeatureSource()
        let storeSource = try [
            "timetracker/Stores/Facade/TimeTrackerStore+InboxCommands.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxReadModels.swift",
            "timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestions.swift",
            "timetracker/Services/Inbox/InboxSuggestionStateService.swift"
        ]
        .map(sourceText)
        .joined(separator: "\n")
        let refreshSource = try sourceText("timetracker/Stores/Refresh/StoreRefreshCoordinator.swift")
        let llmSource = try sourceText("timetracker/Services/LLM/LLMInboxSuggestionService.swift")

        #expect(inboxSource.contains("store.suggestInboxItem(item)") == false)
        #expect(inboxSource.contains("store.presentInboxSuggestionEditor(item)") == false)
        #expect(inboxSource.contains("store.applyInboxSuggestion(item)"))
        #expect(inboxSource.contains("store.discardInboxSuggestion(item)"))
        #expect(inboxSource.contains("store.deleteInboxItem(item)"))
        #expect(inboxSource.contains("canApplySuggestion(for: item)"))
        #expect(inboxSource.contains("canDiscardSuggestion(for: item)"))
        #expect(inboxSource.contains("inbox.suggestion.generating"))
        #expect(inboxSource.contains("InboxSuggestionBar("))
        #expect(inboxSource.contains("InboxSuggestionFailureBar("))
        #expect(inboxSource.contains("store.retryInboxSuggestion(item)"))
        #expect(inboxSource.contains("store.clearInboxSuggestionFailure(item)"))
        #expect(inboxSource.contains("inbox.suggestion.prefix"))
        #expect(inboxSource.contains(".padding(.leading, 74)") == false)
        #expect(storeSource.contains("func autoSuggestInboxItemsIfNeeded()"))
        #expect(storeSource.contains("enum InboxSuggestionStateKind"))
        #expect(storeSource.contains("func shouldAutoSuggest("))
        #expect(storeSource.contains("func canStoreGeneratedSuggestion("))
        #expect(storeSource.contains("func retryInboxSuggestion"))
        #expect(storeSource.contains("inboxSuggestionFailureByItemID"))
        #expect(refreshSource.contains("store.autoSuggestInboxItemsIfNeeded()"))
        #expect(llmSource.contains("allowedSymbols: SymbolCatalog.symbolNames"))
        #expect(llmSource.contains("prefix(400)") == false)
    }

    private func inboxFeatureSource() throws -> String {
        try [
            "timetracker/Features/Inbox/InboxViews.swift",
            "timetracker/Features/Inbox/InboxListView.swift",
            "timetracker/Features/Inbox/InboxCaptureRow.swift",
            "timetracker/Features/Inbox/InboxItemRow.swift",
            "timetracker/Features/Inbox/InboxSuggestionRow.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }

    private func appRootSource() throws -> String {
        try [
            "timetracker/App/ContentView.swift",
            "timetracker/App/RootViews/DesktopRootViews.swift",
            "timetracker/App/RootViews/iOSRootViews.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }

    private func taskEditorFeatureSource() throws -> String {
        try [
            "timetracker/Features/Tasks/Editor/TaskEditorComponents.swift",
            "timetracker/Features/Tasks/Editor/TaskChecklistEditorSection.swift",
            "timetracker/Features/Tasks/Editor/ChecklistEditorRow.swift"
        ]
        .map { try sourceText($0) }
        .joined(separator: "\n")
    }
}
