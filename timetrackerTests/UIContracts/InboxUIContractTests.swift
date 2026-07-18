import Foundation
import Testing

@Suite(.serialized)
struct InboxUIContractTests {
    @Test
    func automaticSuggestionsAreBoundedAndFailuresRequireExplicitRetry() throws {
        let source = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestions.swift")

        #expect(source.contains("maximumInboxSuggestionConcurrency = 3"))
        #expect(source.contains("guard inboxSuggestionInFlightIDs.count < Self.maximumInboxSuggestionConcurrency else"))
        #expect(source.contains("enqueueInboxSuggestion(itemID: item.id, showsErrors: showsErrors)"))
        #expect(source.contains("inboxSuggestionFailureByItemID[item.id] == nil"))
        #expect(source.contains("autoSuggestInboxItemsIfNeeded()"))
        #expect(source.contains("preferences.llmAutomaticSuggestionsEnabled"))
    }

    @Test
    func inboxOwnsNativeDestinationAndStableAccessibleListActions() throws {
        let storeSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore.swift")
        let contentSource = try appRootSource()
        let tasksSource = try sourceText("timetracker/Features/Tasks/Management/TasksViews.swift")
        let inboxSource = try inboxFeatureSource()
        let inboxItemSource = try sourceText("timetracker/Features/Inbox/InboxItemRow.swift")
        let inboxStoreSource = try sourceText("timetracker/Stores/Facade/TimeTrackerStore+InboxCommands.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarViews.swift")
        let layoutSource = try sourceText("timetracker/SharedUI/Foundation/LayoutPolicies.swift")

        #expect(storeSource.contains("case inbox = \"Inbox\""))
        #expect(contentSource.contains("case .inbox:"))
        #expect(contentSource.contains("InboxView(store: store)"))
        #expect(sidebarSource.contains(".accessibilityIdentifier(\"sidebar.\\(destination.rawValue)\")"))
        #expect(tasksSource.contains("InboxNavigationRow(count: store.openInboxItems.count)") == false)
        #expect(inboxSource.contains("List {"))
        #expect(inboxSource.contains(".accessibilityIdentifier(\"inbox.view\")"))
        #expect(inboxSource.contains(".accessibilityIdentifier(\"inbox.capture.add\")"))
        #expect(inboxSource.contains(".accessibilityIdentifier(\"inbox.capture.field\")"))
        #expect(inboxSource.contains("textFieldAccessibilityIdentifier: \"inbox.item.\\(item.id.uuidString)\""))
        #expect(inboxSource.contains(".accessibilityIdentifier(\"inbox.sort\")"))
        #expect(inboxSource.contains("InboxCaptureRow("))
        #expect(inboxSource.contains("InboxListRow("))
        #expect(inboxSource.contains("EditableChecklistTextRow("))
        #expect(inboxSource.contains("showsIcon: false"))
        #expect(inboxSource.contains("InboxCompletedSection("))
        #expect(inboxSource.contains("inbox.completed.disclosure"))
        #expect(inboxSource.contains("if openItems.isEmpty"))
        #expect(inboxSource.contains(".onMove(perform: moveInboxItems)"))
        #expect(inboxSource.contains(".swipeActions(edge: .leading"))
        #expect(inboxSource.contains(".swipeActions(edge: .trailing"))
        #expect(inboxSource.contains(".environment(\\.editMode"))
        #expect(inboxSource.contains("Label(AppStrings.localized(\"inbox.suggestion.apply\"), systemImage: \"checkmark\")"))
        #expect(inboxSource.contains("Label(AppStrings.localized(\"inbox.suggestion.discard\"), systemImage: \"xmark\")"))
        #expect(inboxSource.contains("Label(AppStrings.delete, systemImage: \"trash\")"))
        #expect(inboxSource.contains("isDeleteConfirmationPresented"))
        #expect(inboxSource.contains("inbox.delete.confirm.message"))
        #expect(inboxSource.contains(".accessibilityHint(AppStrings.localized(\"inbox.capture.hint\"))"))
        #expect(inboxSource.contains("inbox.empty.description"))
        #expect(inboxSource.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(inboxSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(inboxSource.contains(".accessibilityHint(Text(.app(\"inbox.empty.description\")))"))
        #expect(inboxSource.contains("Image(systemName: \"ellipsis\")"))
        #expect(inboxSource.contains(".accessibilityLabel(AppStrings.localized(\"common.more\"))"))
        #expect(inboxSource.contains("inbox.item.menu.\\(item.id.uuidString)"))
        #expect(inboxSource.contains("if item.isCompleted == false"))
        #expect(inboxSource.contains("systemImage: \"folder\""))
        #expect(inboxSource.contains("InboxMoveToTaskBaseline(item: item)"))
        #expect(inboxSource.contains("context: .inboxDestination"))
        #expect(inboxSource.contains("store.moveInboxItem(\n                baseline: baseline,"))
        #expect(inboxSource.contains("inbox.moveToTask.\\(item.id.uuidString)"))
        #expect(inboxSource.contains("common.sort"))
        #expect(inboxItemSource.contains("common.sort") == false)
        #expect(inboxSource.contains(".navigationTitle(AppStrings.inbox)"))
        #expect(inboxSource.contains(".navigationBarTitleDisplayMode(.large)"))
        #expect(inboxSource.contains(".listStyle(.plain)"))
        #expect(inboxSource.contains("inbox.subtitle") == false)
        #expect(inboxSource.contains("inbox.footer") == false)
        #expect(inboxSource.contains("let submit: () -> Bool"))
        #expect(inboxSource.contains("draft.submit(using: store.addInboxItem(title:))"))
        #expect(inboxSource.contains("if submit() {\n            title = \"\"\n        }") == false)
        #expect(inboxStoreSource.contains("suggestInboxItem(updatedItem, showsErrors: false)"))
        #expect(inboxStoreSource.contains("func reorderInboxItems(sourceOffsets: IndexSet, destination: Int)"))
        #expect(inboxStoreSource.contains("StoreScopedInboxCommandCoordinator("))
        #expect(inboxStoreSource.contains("InboxOrderMutationBaseline(items: currentItems)"))
        #expect(inboxSource.contains("rowHeight(forTitle:") == false)
        #expect(inboxSource.contains("estimatedTitleLineCount") == false)
        #expect(layoutSource.contains("rowHeight(forTitle:") == false)
        #expect(layoutSource.contains("estimatedTitleLineCount") == false)
    }

    @Test
    func inboxCaptureValidatesBeforeSubmittingAndKeepsErrorsAdjacent() throws {
        let captureSource = try sourceText("timetracker/Features/Inbox/InboxCaptureRow.swift")
        let english = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(captureSource.contains("InboxPersistencePolicy.prepareItem("))
        #expect(captureSource.contains("guard canSubmit else { return }"))
        #expect(captureSource.contains(".disabled(canSubmit == false)"))
        #expect(captureSource.contains("inbox.capture.submit"))
        #expect(english.contains("\"inbox.capture.submit\" = \"Add\";"))
        #expect(captureSource.contains("inbox.capture.validation"))
        #expect(captureSource.contains(".accessibilityAddTraits(.isStaticText)"))
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
        #expect(inboxSource.contains("private var canApplySuggestion: Bool"))
        #expect(inboxSource.contains("private var canDiscardSuggestion: Bool"))
        #expect(inboxSource.contains("inbox.suggestion.generating"))
        #expect(inboxSource.contains("InboxSuggestionBar("))
        #expect(inboxSource.contains("InboxSuggestionFailureBar("))
        #expect(inboxSource.contains("store.retryInboxSuggestion(item)"))
        #expect(inboxSource.contains("store.clearInboxSuggestionFailure(item)"))
        #expect(inboxSource.contains("inbox.suggestion.targetFormat"))
        #expect(inboxSource.contains("InboxSuggestionBackground") == false)
        #expect(inboxSource.contains(".padding(.leading, 44)"))
        #expect(storeSource.contains("func autoSuggestInboxItemsIfNeeded()"))
        #expect(storeSource.contains("enum InboxSuggestionStateKind"))
        #expect(storeSource.contains("func shouldAutoSuggest("))
        #expect(storeSource.contains("func canStoreGeneratedSuggestion("))
        #expect(storeSource.contains("func retryInboxSuggestion"))
        #expect(storeSource.contains("inboxSuggestionFailureByItemID"))
        #expect(refreshSource.contains("store.autoSuggestInboxItemsIfNeeded()"))
        #expect(llmSource.contains("allowedSymbols: SymbolCatalog.aiSuggestionSymbolNames"))
        #expect(llmSource.contains("maximumRequestBodyByteCount"))
        #expect(llmSource.contains("prefix(400)") == false)
    }

    @Test
    func inboxSuggestionEmphasisUsesModernTextInterpolation() throws {
        let source = try sourceText("timetracker/Features/Inbox/InboxSuggestionRow.swift")

        #expect(source.contains("inbox.suggestion.targetFormat"))
        #expect(source.contains("String.localizedStringWithFormat("))
        #expect(source.contains("+ Text(taskTitle)") == false)
    }

    @Test
    func inboxMovePickerCopyExistsInEveryMainAppLocale() throws {
        let requiredKeys = [
            "inbox.moveToTask",
            "inbox.moveToTask.title",
            "inbox.moveToTask.emptyDescription",
            "inbox.moveToTask.selectionHint",
            "tasks.search.empty.description",
            "pomodoro.taskPicker.selectionHint"
        ]

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let source = try sourceText(
                "timetracker/\(locale).lproj/Localizable.strings"
            )
            for key in requiredKeys {
                #expect(source.contains("\"\(key)\" ="))
            }
        }
    }

    private func inboxFeatureSource() throws -> String {
        try [
            "timetracker/Features/Inbox/InboxViews.swift",
            "timetracker/Features/Inbox/InboxCompletedSection.swift",
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

}
