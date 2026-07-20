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
        #expect(inboxSource.contains("contentAlignment: .center"))
        #expect(
            inboxSource.contains(
                "completionVisualSize: InboxItemLayout.completionVisualSize"
            )
        )
        #expect(
            inboxSource.contains(
                "(AppLayout.minimumInteractiveTarget - completionVisualSize) / 2"
            )
        )
        #expect(
            inboxSource.contains(
                "completionAccessibilityIdentifier:\n" +
                    "                        \"inbox.item.completion.\\(item.id.uuidString)\""
            )
        )
        #expect(inboxSource.components(separatedBy: "Section {").count - 1 >= 4)
        #expect(inboxSource.contains("if !openItems.isEmpty {\n                Section {"))
        #expect(inboxSource.contains("InboxCompletedSection("))
        #expect(inboxSource.contains("inbox.completed.disclosure"))
        #expect(inboxSource.contains("if openItems.isEmpty"))
        #expect(inboxSource.contains(".onMove(perform: moveInboxItems)"))
        #expect(inboxSource.contains(".swipeActions(edge: .leading"))
        #expect(inboxSource.contains(".swipeActions(edge: .trailing"))
        #expect(inboxSource.contains(".environment(\\.editMode"))
        #expect(inboxSource.contains("Label(action.destination.applyTitle, systemImage: \"checkmark\")"))
        #expect(inboxSource.contains("Label(AppStrings.localized(\"inbox.suggestion.discard\"), systemImage: \"xmark\")"))
        #expect(inboxSource.contains("Label(AppStrings.delete, systemImage: \"trash\")"))
        #expect(inboxSource.contains("isDeleteConfirmationPresented"))
        #expect(inboxSource.contains("inbox.delete.confirm.message"))
        #expect(inboxSource.contains(".accessibilityHint(AppStrings.localized(\"inbox.capture.hint\"))"))
        #expect(inboxSource.contains("inbox.empty.description"))
        #expect(inboxSource.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(inboxSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(inboxSource.contains(".accessibilityHint(Text(.app(\"inbox.empty.description\")))"))
        #expect(inboxSource.contains("TrailingMenuLabel(systemImage: \"ellipsis\")"))
        #expect(inboxSource.contains(".accessibilityLabel(AppStrings.localized(\"common.more\"))"))
        #expect(inboxSource.contains("inbox.item.menu.\\(item.id.uuidString)"))
        #expect(inboxSource.contains("if item.isCompleted == false"))
        #expect(inboxSource.contains("systemImage: \"arrow.turn.down.right\""))
        #expect(inboxSource.contains("systemImage: \"square.grid.2x2\""))
        #expect(inboxSource.contains("systemImage: \"checklist\""))
        #expect(inboxSource.contains("InboxManualRouteBaseline(item: item)"))
        #expect(inboxSource.contains("context: .inboxChildTaskParent"))
        #expect(inboxSource.contains("context: .inboxTaskDestination"))
        #expect(inboxSource.contains("context: .inboxChecklistTarget"))
        #expect(inboxSource.contains("store.routeInboxItemAsChildTask("))
        #expect(inboxSource.contains("store.routeInboxItemToCategory("))
        #expect(inboxSource.contains("store.routeInboxItemAsChecklist("))
        #expect(inboxSource.contains("inbox.route.childTask.\\(item.id.uuidString)"))
        #expect(inboxSource.contains("inbox.route.categoryTask.\\(item.id.uuidString)"))
        #expect(inboxSource.contains("inbox.route.checklistItem.\\(item.id.uuidString)"))
        #expect(inboxSource.contains("common.sort"))
        #expect(inboxItemSource.contains("common.sort") == false)
        #expect(inboxSource.contains(".navigationTitle(AppStrings.inbox)"))
        #expect(inboxSource.contains(".navigationBarTitleDisplayMode(.large)"))
        #expect(inboxSource.contains(".listStyle(.insetGrouped)"))
        #expect(inboxSource.contains(".scrollContentBackground(.hidden)"))
        #expect(inboxSource.contains(".listStyle(.plain)") == false)
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
        let suggestionSource = try sourceText(
            "timetracker/Features/Inbox/InboxSuggestionRow.swift"
        )
        let readySuggestionRemainder = try #require(
            suggestionSource.components(
                separatedBy: "struct InboxSuggestionBar"
            ).last
        )
        let readySuggestionSource = try #require(
            readySuggestionRemainder.components(
                separatedBy: "struct InboxSuggestionFailureBar"
            ).first
        )
        let checklistSource = try sourceText(
            "timetracker/SharedUI/Components/ChecklistControls.swift"
        )
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
        let commandSource = try sourceText(
            "timetracker/Stores/Facade/TimeTrackerStore+InboxSuggestionCommands.swift"
        )

        #expect(inboxSource.contains("store.suggestInboxItem(item)") == false)
        #expect(inboxSource.contains("store.presentInboxSuggestionEditor(item)") == false)
        #expect(inboxSource.contains("let applyBaseline = InboxSuggestionApplyBaseline("))
        #expect(inboxSource.contains("store.applyInboxSuggestion(baseline: applyBaseline)"))
        #expect(inboxSource.contains("store.applyInboxSuggestion(baseline: action.baseline)"))
        #expect(inboxSource.contains("private var applicableSuggestionAction:"))
        #expect(inboxSource.contains("store.applyInboxSuggestion(item)") == false)
        #expect(commandSource.contains("func applyInboxSuggestion(baseline: InboxSuggestionApplyBaseline)"))
        #expect(commandSource.contains("inboxSuggestion(for: item)") == false)
        #expect(inboxSource.contains("store.discardInboxSuggestion(item)"))
        #expect(inboxSource.contains("store.deleteInboxItem(item)"))
        #expect(inboxSource.contains("private var canDiscardSuggestion: Bool"))
        #expect(inboxSource.contains("inbox.suggestion.generating"))
        #expect(inboxSource.contains("InboxSuggestionBar("))
        #expect(inboxSource.contains("InboxSuggestionFailureBar("))
        #expect(inboxSource.contains("store.retryInboxSuggestion(item)"))
        #expect(inboxSource.contains("store.clearInboxSuggestionFailure(item)"))
        #expect(inboxSource.contains("inbox.suggestion.label"))
        #expect(inboxSource.contains("inbox.suggestion.destination.childTaskFormat"))
        #expect(inboxSource.contains("inbox.suggestion.destination.categoryFormat"))
        #expect(inboxSource.contains("inbox.suggestion.destination.checklistFormat"))
        #expect(inboxSource.contains("automationIdentifier: String"))
        #expect(inboxSource.contains("kind?.rawValue ?? \"invalid\""))
        #expect(inboxSource.contains("Text(destination.summary)"))
        #expect(inboxSource.contains(".accessibilityLabel(destination.summary)"))
        #expect(inboxSource.contains(".disabled(destination.isAvailable == false)"))
        #expect(inboxSource.contains("InboxSuggestionBackground") == false)
        #expect(inboxSource.contains(".padding(.leading, 44)") == false)
        #expect(
            readySuggestionSource.contains(
                "InboxItemLayout.completionMarkLeadingInset"
            )
        )
        #expect(
            readySuggestionSource.contains(
                "AppLayout.minimumInteractiveTarget + 10"
            ) == false
        )
        #expect(checklistSource.contains("var contentAlignment: VerticalAlignment = .top"))
        #expect(checklistSource.contains("HStack(alignment: contentAlignment, spacing: 10)"))
        #expect(checklistSource.contains("completionAccessibilityIdentifier"))
        #expect(inboxSource.contains("iconName: suggestion.iconName"))
        #expect(inboxSource.contains("colorHex: suggestion.colorHex"))
        #expect(inboxSource.contains("ChecklistItemIcon("))
        #expect(inboxSource.contains("style: .solid"))
        #expect(checklistSource.contains("enum ChecklistItemIconStyle"))
        #expect(
            checklistSource.contains(
                "TaskColorPalette.contrastingForegroundColor(for: sanitizedColor)"
            )
        )
        #expect(inboxSource.contains("message: failureMessage"))
        #expect(inboxSource.contains("Text(message)"))
        #expect(inboxSource.contains("inbox.suggestion.targetUnavailable"))
        #expect(inboxSource.contains("inbox.suggestion.missingTarget"))
        #expect(inboxSource.contains("} else if let suggestion {"))
        #expect(inboxSource.contains("inboxSuggestionDestinationPresentation("))
        #expect(inboxSource.contains("suggestion.manualRouteDestination"))
        #expect(inboxSource.contains("case let .childTask(parentTaskID):"))
        #expect(inboxSource.contains("case let .category(categoryID):"))
        #expect(inboxSource.contains("case let .checklist(taskID):"))
        #expect(inboxSource.contains("trackableTaskIDs.contains(parentTaskID)"))
        #expect(inboxSource.contains("trackableTaskIDs.contains(taskID)"))
        #expect(inboxSource.contains("@Environment(\\.accessibilityReduceMotion)"))
        #expect(inboxSource.contains(".snappy(duration: 0.22)"))
        #expect(inboxSource.contains("reduceMotion\n            ? .opacity"))
        #expect(inboxSource.contains("inbox.suggestion.generating.\\(itemID.uuidString)"))
        #expect(
            inboxSource.contains(
                "inbox.suggestion.ready.\\(destination.automationIdentifier)."
            )
        )
        #expect(inboxSource.contains("inbox.suggestion.failure.\\(itemID.uuidString)"))
        #expect(
            inboxSource.contains(
                "inbox.suggestion.apply.\\(destination.automationIdentifier)."
            )
        )
        #expect(inboxSource.contains("inbox.suggestion.discard.\\(itemID.uuidString)"))
        #expect(inboxSource.contains("inbox.suggestion.retry.\\(itemID.uuidString)"))
        #expect(inboxSource.contains("CompactTextActionLabel("))
        #expect(inboxSource.contains("compactActionButton("))
        #expect(inboxSource.contains("regularActionButton("))
        #expect(inboxSource.contains("systemImage: \"xmark\""))
        #expect(inboxSource.contains("systemImage: \"checkmark\""))
        #expect(inboxSource.contains(".buttonStyle(.borderedProminent)"))
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
        let source = try sourceText(
            "timetracker/Features/Inbox/InboxSuggestionDestinationPresentation.swift"
        )

        #expect(source.contains("String.localizedStringWithFormat("))
        #expect(source.contains("inbox.suggestion.destination.childTaskFormat"))
        #expect(source.contains("inbox.suggestion.destination.categoryFormat"))
        #expect(source.contains("inbox.suggestion.destination.checklistFormat"))
        #expect(source.contains("+ Text(targetTitle)") == false)
    }

    @Test
    func inboxRoutePickerCopyExistsInEveryMainAppLocale() throws {
        let requiredKeys = [
            "inbox.route.childTask",
            "inbox.route.childTask.title",
            "inbox.route.childTask.emptyDescription",
            "inbox.route.childTask.selectionHint",
            "inbox.route.categoryTask",
            "inbox.route.categoryTask.title",
            "inbox.route.categoryTask.empty",
            "inbox.route.categoryTask.emptyDescription",
            "inbox.route.categoryTask.selectionHint",
            "inbox.route.checklistItem",
            "inbox.route.checklistItem.title",
            "inbox.route.checklistItem.emptyDescription",
            "inbox.route.checklistItem.selectionHint",
            "taskCategory.searchPrompt",
            "taskCategory.search.empty",
            "taskCategory.search.emptyDescription",
            "inbox.suggestion.label",
            "inbox.suggestion.apply.childTask",
            "inbox.suggestion.apply.category",
            "inbox.suggestion.apply.checklist",
            "inbox.suggestion.apply.unavailable",
            "inbox.suggestion.destination.childTaskFormat",
            "inbox.suggestion.destination.categoryFormat",
            "inbox.suggestion.destination.checklistFormat",
            "inbox.suggestion.destination.invalidFormat",
            "tasks.search.empty.description",
            "pomodoro.taskPicker.selectionHint"
        ]
        let formatKeys = [
            "inbox.suggestion.destination.childTaskFormat",
            "inbox.suggestion.destination.categoryFormat",
            "inbox.suggestion.destination.checklistFormat",
            "inbox.suggestion.destination.invalidFormat"
        ]

        for locale in ["en", "zh-Hans", "zh-Hant"] {
            let source = try sourceText(
                "timetracker/\(locale).lproj/Localizable.strings"
            )
            for key in requiredKeys {
                #expect(source.contains("\"\(key)\" ="))
            }
            for key in formatKeys {
                let line = try #require(
                    source.split(separator: "\n").first {
                        $0.hasPrefix("\"\(key)\" =")
                    }
                )
                #expect(
                    String(line).components(separatedBy: "%@").count - 1 == 1
                )
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
            "timetracker/Features/Inbox/InboxSuggestionDestinationPresentation.swift",
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
