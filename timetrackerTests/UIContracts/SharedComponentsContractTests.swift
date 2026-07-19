import Foundation
import Testing

@Suite(.serialized)
struct SharedComponentsContractTests {
    @Test
    func accessibilityTextUsesAlternateRowsAndNonScalingDecorativeIcons() throws {
        let homeSource = try [
            "timetracker/Features/Home/PhoneHomeView.swift",
            "timetracker/Features/Home/PhoneHomeRows.swift",
            "timetracker/Features/Home/Rows/HomeTimerRows.swift"
        ].map(sourceText).joined(separator: "\n")
        let settingsSource = try [
            "timetracker/Features/Settings/SettingsViews.swift",
            "timetracker/Features/Settings/SettingsCategoryViews.swift",
            "timetracker/SharedUI/Components/SettingsRows.swift",
            "timetracker/SharedUI/Components/SettingsPresentationModifiers.swift",
            "timetracker/SharedUI/Components/SettingsInputRows.swift",
            "timetracker/SharedUI/Components/SettingsActionRows.swift",
            "timetracker/SharedUI/Components/SettingsSyncFeedbackRow.swift",
            "timetracker/Features/Settings/SettingsDataSectionsViews.swift",
            "timetracker/Features/Settings/DisplayTimingSettingsSection.swift",
            "timetracker/Features/Settings/PomodoroSettingsSection.swift",
            "timetracker/Features/Settings/PomodoroPickerViews.swift",
            "timetracker/Features/Settings/CountdownSettingsSection.swift",
            "timetracker/Features/Settings/SyncSettingsSection.swift",
            "timetracker/Features/Settings/SyncRecoverySettingsSection.swift",
            "timetracker/Features/Settings/LLMSettingsViews.swift",
            "timetracker/Features/Settings/LLMSettingsSection.swift"
        ].map(sourceText).joined(separator: "\n")
        let designSystemSource = try sourceText("timetracker/SharedUI/Foundation/DesignSystem.swift")

        #expect(homeSource.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(homeSource.contains("private var accessibilityContent"))
        #expect(homeSource.contains(".contentMargins(.bottom"))
        #expect(settingsSource.contains("dynamicTypeSize.isAccessibilitySize"))
        #expect(settingsSource.contains("private var accessibilityCategoryRow"))
        #expect(settingsSource.contains("private var descriptiveCategoryRow"))
        #expect(settingsSource.contains(".lineLimit(2)"))
        #expect(settingsSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(settingsSource.contains(".font(.system(size: 18, weight: .semibold))"))
        #expect(designSystemSource.contains(".font(.system(size: 17, weight: .semibold))"))
    }

    @Test
    func ipadSplitViewUsesTheNativeAdaptiveSidebarControl() throws {
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(ipadSource.contains("preferredCompactColumn: $preferredCompactColumn"))
        #expect(ipadSource.contains("preferredCompactColumn = .detail"))
        #expect(ipadSource.contains("SidebarRevealButton") == false)
        #expect(ipadSource.contains("ToolbarItem(placement: .topBarLeading)") == false)
        #expect(ipadSource.contains("isInspectorPresented") == false)
        #expect(ipadSource.contains(".inspector(") == false)
    }

    @Test
    func sectionHeadersUseSharedComponentAcrossSettingsAndHome() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SectionHeaders.swift")
        let settingsSupportSource = try sourceText("timetracker/Features/Settings/Support/SettingsSupportViews.swift")
        let homeSource = try [
            "timetracker/Features/Home/Sections/HomeTimelineViews.swift",
            "timetracker/Features/Home/Sections/HomeForecastViews.swift",
            "timetracker/Features/Home/Sections/HomeCountdownViews.swift"
        ].map(sourceText).joined(separator: "\n")

        #expect(sharedSource.contains("struct AppSectionHeader"))
        #expect(sharedSource.contains("struct SettingsHeader"))
        #expect(sharedSource.contains("struct SectionTitle"))
        #expect(settingsSupportSource.contains("struct SettingsHeader") == false)
        #expect(homeSource.contains("SectionTitle(title:"))
    }

    @Test
    func primaryActionLabelsWrapLegiblyAndExposeStableActions() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/ActionControls.swift")
        let homeSource = try [
            "timetracker/Features/Home/Controls/HomeActionsViews.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPicker.swift",
            "timetracker/SharedUI/Components/TaskHierarchyPickerPresentation.swift"
        ].map(sourceText).joined(separator: "\n")
        let homeTimelineSource = try sourceText("timetracker/Features/Home/Sections/HomeTimelineViews.swift")
        let taskDetailSource = try sourceText("timetracker/Features/Tasks/Detail/TaskDetailActionsView.swift")

        #expect(sharedSource.contains("struct AppActionLabel"))
        #expect(sharedSource.contains(".lineLimit(2)"))
        #expect(sharedSource.contains(".multilineTextAlignment(.center)"))
        #expect(sharedSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(sharedSource.contains(".frame(height: dynamicTypeSize.isAccessibilitySize ? nil : fixedHeight)"))
        #expect(sharedSource.contains("dynamicTypeSize.isAccessibilitySize || fixedHeight == nil"))
        #expect(sharedSource.contains(".padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 4 : 0)"))
        #expect(homeSource.contains("AppActionLabel(title: actionTitle"))
        #expect(homeSource.contains(".accessibilityIdentifier(\"home.startTimer\")"))
        #expect(homeTimelineSource.contains("SectionTitle(title: AppStrings.localized(\"home.now.title\"))\n                .accessibilityIdentifier(\"home.activeTimers\")"))
        #expect(homeTimelineSource.contains("        .accessibilityIdentifier(\"home.activeTimers\")\n    }\n}\n\nstruct TimelineSection") == false)
        #expect(homeSource.contains("home.switchTimer"))
        #expect(homeSource.contains("home.newTask") == false)
        #expect(taskDetailSource.contains("AppActionLabel(title: AppStrings.startTimer"))
        #expect(taskDetailSource.contains("AppActionLabel(title: AppStrings.addTime"))
        #expect(taskDetailSource.contains(".accessibilityIdentifier(\"task.detail.actions\")"))
    }

    @Test
    func trailingMenuLabelsAlignVisibleActionsWithoutShrinkingHitTargets() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/ActionControls.swift")
        let categorySource = try sourceText("timetracker/SharedUI/Components/TaskCategoryViews.swift")
        let timelineSource = try sourceText("timetracker/Features/Home/Rows/HomeTimelineRows.swift")
        let inboxSource = try sourceText("timetracker/Features/Inbox/InboxItemRow.swift")

        #expect(sharedSource.contains("struct TrailingMenuLabel"))
        #expect(sharedSource.contains("minWidth: AppLayout.minimumInteractiveTarget"))
        #expect(sharedSource.contains("minHeight: AppLayout.minimumInteractiveTarget"))
        #expect(sharedSource.contains("alignment: .trailing"))
        #expect(sharedSource.contains(".contentShape(Rectangle())"))
        #expect(categorySource.contains("TrailingMenuLabel(systemImage: \"ellipsis.circle\")"))
        #expect(timelineSource.contains("TrailingMenuLabel(systemImage: \"ellipsis\")"))
        #expect(inboxSource.contains("TrailingMenuLabel(systemImage: \"ellipsis\")"))
        #expect(categorySource.contains(".frame(minWidth: AppLayout.minimumInteractiveTarget") == false)
        #expect(timelineSource.contains(".frame(width: 44, height: 44)") == false)
        #expect(timelineSource.contains(".padding(.trailing, isCompactPhone ? 0 : 14)"))
        #expect(timelineSource.contains(".padding(.horizontal, 14)") == false)
        #expect(inboxSource.contains(".frame(width: 44, height: 44)") == false)
    }

    @Test
    func settingsActionRowsUseSharedComponent() throws {
        let sharedSource = try [
            "timetracker/SharedUI/Components/SettingsRows.swift",
            "timetracker/SharedUI/Components/SettingsPresentationModifiers.swift",
            "timetracker/SharedUI/Components/SettingsInputRows.swift",
            "timetracker/SharedUI/Components/SettingsActionRows.swift",
            "timetracker/SharedUI/Components/SettingsSyncFeedbackRow.swift"
        ].map(sourceText).joined(separator: "\n")
        let settingsSource = try [
            "timetracker/Features/Settings/DisplayTimingSettingsSection.swift",
            "timetracker/Features/Settings/PomodoroSettingsSection.swift",
            "timetracker/Features/Settings/PomodoroPickerViews.swift",
            "timetracker/Features/Settings/CountdownSettingsSection.swift",
            "timetracker/Features/Settings/SyncSettingsSection.swift",
            "timetracker/Features/Settings/SyncRecoverySettingsSection.swift",
            "timetracker/Features/Settings/LLMSettingsViews.swift",
            "timetracker/Features/Settings/LLMSettingsSection.swift",
            "timetracker/Features/Settings/SettingsDataSectionsViews.swift",
            "timetracker/Features/Settings/Support/SettingsSupportViews.swift"
        ].map(sourceText).joined(separator: "\n")
        let settingsActionsSource = try sourceText("timetracker/Features/Settings/SettingsViewActions.swift")

        #expect(sharedSource.contains("struct SettingsActionLabel"))
        #expect(sharedSource.contains("struct SettingsDestructiveActionLabel"))
        #expect(sharedSource.contains("struct SettingsStatusRow"))
        #expect(sharedSource.contains("func settingsRowSeparatorAligned()"))
        #expect(sharedSource.contains("alignmentGuide(.listRowSeparatorLeading)"))
        #expect(sharedSource.contains(".font(.body)"))
        #expect(settingsSource.contains("SettingsActionLabel("))
        #expect(settingsSource.contains("SettingsDestructiveActionLabel("))
        #expect(settingsSource.contains("SettingsStatusRow(feedback: feedback)"))
        #expect(settingsSource.contains(".settingsRowSeparatorAligned()"))
        #expect(settingsActionsSource.contains("store.syncStatus.feedback("))
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.exportJSON\")") == false)
        #expect(settingsSource.contains("Label(AppStrings.localized(\"settings.forceSync\")") == false)
        #expect(settingsSource.contains("Button(role: .destructive, action: onRebuildDemoData) {\n                Text(") == false)
    }

    @Test
    func llmConfigurationUsesAnExplicitTestAndSaveDraft() throws {
        let llmSource = try [
            "timetracker/Features/Settings/LLMSettingsViews.swift",
            "timetracker/Features/Settings/LLMSettingsSection.swift"
        ].map(sourceText).joined(separator: "\n")
        let settingsViewSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let englishStrings = try sourceText("timetracker/en.lproj/Localizable.strings")

        #expect(llmSource.contains("struct LLMConfigurationDraft: Equatable"))
        #expect(llmSource.contains("Button(action: testConnection)"))
        #expect(llmSource.contains("Button(AppStrings.localized(\"common.save\"), action: save)"))
        #expect(llmSource.contains(".editorDiscardConfirmation("))
        #expect(settingsViewSource.contains("@Environment(AppPresentationRouter.self)"))
        #expect(settingsViewSource.contains(".sheet(") == false)
        #expect(settingsViewSource.contains("isLLMConfigurationPresented") == false)
        let settingsSectionsSource = try sourceText(
            "timetracker/Features/Settings/SettingsCategorySections.swift"
        )
        let presentationHostSource = try sourceText(
            "timetracker/App/AppPresentationHost.swift"
        )
        #expect(settingsSectionsSource.contains("onConfigure: presentLLMConfiguration"))
        #expect(settingsViewSource.contains("presentationRouter.presentLLMConfiguration(using: store)"))
        #expect(presentationHostSource.contains("store.setLLMConfiguration("))
        #expect(settingsViewSource.contains("store.setLLMEndpoint(configuration.endpoint)") == false)
        #expect(englishStrings.contains("\"settings.llm.testConnection\""))
    }

    @Test
    func settingsDiscardsModelResponsesAfterCredentialsChange() throws {
        let source = try sourceText("timetracker/Features/Settings/LLMSettingsViews.swift")

        #expect(source.contains("fetchTask?.cancel()"))
        #expect(source.components(separatedBy: "draft.credentialFingerprint == fingerprint").count == 3)
        #expect(source.contains("guard !Task.isCancelled"))
    }

    @Test
    func selectedTaskPulseIsSharedForSidebarRows() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SelectionPulse.swift")
        let sidebarSource = try sourceText("timetracker/Features/Sidebar/SidebarTaskTreeViews.swift")

        #expect(sharedSource.contains("struct TaskSelectionPulseModifier<"))
        #expect(sharedSource.contains("func taskSelectionPulse<"))
        #expect(sidebarSource.contains(".taskSelectionPulse("))
        #expect(sidebarSource.contains("@State private var isPulsing") == false)
    }

    @Test
    func taskSurfacesReuseCanonicalSummaryAndTimerActionComponents() throws {
        let summary = try sourceText(
            "timetracker/SharedUI/Components/TaskSummaryRow.swift"
        )
        let timerAction = try sourceText(
            "timetracker/SharedUI/Components/TaskTimerActionButton.swift"
        )
        let identity = try sourceText(
            "timetracker/SharedUI/Components/TaskIdentityRow.swift"
        )
        let tasks = try sourceText(
            "timetracker/Features/Tasks/Management/TaskManagementRowContent.swift"
        )
        let sidebar = try sourceText(
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift"
        )
        let picker = try sourceText(
            "timetracker/SharedUI/Components/TaskHierarchyPickerRows.swift"
        )
        let home = try sourceText(
            "timetracker/Features/Home/Rows/HomeTimerRows.swift"
        )
        let iconControlDimensionSource =
            "private var iconControlDimension: CGFloat {\n" +
            "        #if os(iOS)\n" +
            "        54\n" +
            "        #else\n" +
            "        28\n" +
            "        #endif\n" +
            "    }"

        #expect(tasks.contains("TaskSummaryRow("))
        #expect(sidebar.contains("TaskSummaryRow("))
        #expect(picker.contains("TaskSummaryRow("))
        #expect(identity.contains("TaskSummaryRow("))
        #expect(identity.contains("TaskIcon(") == false)
        #expect(summary.contains("CompactChecklistProgressLine("))
        #expect(summary.contains("TaskRunningIndicator()"))
        #expect(summary.contains("DurationFormatter.compact(workedSeconds)"))
        #expect(
            summary.contains(
                "HStack(spacing: 8) {\n" +
                    "                        checklistProgress\n" +
                    "                        Spacer(minLength: 8)\n" +
                    "                        trailingFacts"
            )
        )
        #expect(
            summary.contains(
                "if metadata.isRunning {\n" +
                    "                TaskRunningIndicator()\n" +
                    "            }\n\n" +
                    "            if let workedSeconds = metadata.workedSeconds"
            )
        )
        #expect(picker.contains("TaskTimerActionButton("))
        #expect(
            picker.components(separatedBy: "TaskTimerActionButton(").count >= 3
        )
        #expect(picker.contains("activeSegment: nil"))
        #expect(picker.contains("activeSegment: activeSegment"))
        #expect(picker.contains("pickerActionLabelStyle: TaskTimerActionLabelStyle {\n        .iconOnly"))
        #expect(home.contains("TaskTimerActionButton("))
        #expect(timerAction.contains("enum TaskTimerActionLabelStyle"))
        #expect(
            timerAction.contains(
                "width: usesIconOnly ? iconControlDimension : nil"
            )
        )
        #expect(timerAction.contains("private var minimumControlHeight: CGFloat"))
        #expect(timerAction.contains("private var minimumLabelDimension: CGFloat"))
        #expect(timerAction.contains(iconControlDimensionSource))
        #expect(timerAction.contains(".controlSize(platformControlSize)"))
        #expect(timerAction.contains("private var platformControlSize: ControlSize"))
        #expect(timerAction.contains("timer.action.stopTaskFormat"))
        #expect(timerAction.contains("timer.task.stopHint"))
        #expect(home.contains("HomeTimerTaskAction") == false)
        #expect(home.contains("HomeTimerActionLabelStyle") == false)
        #expect(picker.contains("RunningStatusBadge()") == false)
    }

    @Test
    func sidebarUsesTheSharedInlineTaskSummaryWithoutStatusDrivenRowHeight() throws {
        let summary = try sourceText(
            "timetracker/SharedUI/Components/TaskSummaryRow.swift"
        )
        let sidebar = try sourceText(
            "timetracker/Features/Sidebar/SidebarTaskTreeViews.swift"
        )

        #expect(summary.contains("enum TaskSummaryRowLayout"))
        #expect(summary.contains("case stacked"))
        #expect(summary.contains("case inline"))
        #expect(summary.contains("HStack(alignment: .center, spacing: 12)"))
        #expect(summary.contains("primaryLineLimit: 1"))
        #expect(summary.contains("showsProgressBar: layout == .stacked"))
        #expect(
            summary.contains(".fixedSize(horizontal: true, vertical: false)") == false
        )
        #expect(
            summary.contains(
                "minHeight: activeLayout == .stacked ? minimumRowHeight : nil"
            )
        )
        #expect(sidebar.contains("TaskSummaryRow("))
        #expect(sidebar.contains("layout: .inline"))
        #expect(sidebar.contains(".frame(minHeight: minimumRowHeight)"))
        #expect(sidebar.contains("Image(systemName: \"timer\")") == false)
    }

    @Test
    func splitViewReliesOnTheSystemSidebarToggleInsteadOfDuplicateChrome() throws {
        let sharedSource = try sourceText("timetracker/SharedUI/Components/SplitViewToolbarButtons.swift")
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")
        let desktopSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")

        #expect(sharedSource.contains("struct SidebarRevealButton"))
        #expect(sharedSource.contains("Label(AppStrings.localized(\"sidebar.show\"), systemImage: \"sidebar.left\")"))
        #expect(sharedSource.contains(".labelStyle(.iconOnly)"))
        #expect(ipadSource.contains("SidebarRevealButton") == false)
        #expect(sharedSource.contains("InspectorToggleButton") == false)
        #expect(ipadSource.contains("InspectorToggleButton") == false)
        #expect(desktopSource.contains("InspectorToggleButton") == false)
        #expect(ipadSource.contains("Image(systemName: \"sidebar.right\")") == false)
        #expect(desktopSource.contains("Image(systemName: \"sidebar.right\")") == false)
    }

    @Test
    func settingsUsesPlatformSurfaceAndRootsOmitInspector() throws {
        let appSource = try sourceText("timetracker/App/timetrackerApp.swift")
        let settingsSource = try sourceText("timetracker/Features/Settings/SettingsViews.swift")
        let desktopSource = try sourceText("timetracker/App/RootViews/DesktopRootViews.swift")
        let ipadSource = try sourceText("timetracker/App/RootViews/iOSRootViews.swift")

        #expect(appSource.contains("Settings {\n            SettingsSceneView(store: store)"))
        #expect(appSource.contains("ContentView(store: store)"))
        #expect(settingsSource.contains("Form {"))
        #expect(settingsSource.contains(".formStyle(.grouped)"))
        #expect(desktopSource.contains(".inspector(") == false)
        #expect(ipadSource.contains(".inspector(") == false)
        #expect(desktopSource.contains(".inspectorColumnWidth(") == false)
        #expect(ipadSource.contains(".inspectorColumnWidth(") == false)
    }

    @Test
    func compactActionsAdaptLayoutAndKeepAccessibleHitTargets() throws {
        let actionSource = try sourceText("timetracker/SharedUI/Components/ActionControls.swift")
        let homeActionSource = try sourceText("timetracker/Features/Home/Controls/HomeActionsViews.swift")
        let inboxSuggestionSource = try sourceText("timetracker/Features/Inbox/InboxSuggestionRow.swift")
        let readySuggestionRemainder = try #require(
            inboxSuggestionSource.components(
                separatedBy: "struct InboxSuggestionBar"
            ).last
        )
        let readySuggestionSource = try #require(
            readySuggestionRemainder.components(
                separatedBy: "struct InboxSuggestionFailureBar"
            ).first
        )

        #expect(actionSource.contains(".lineLimit(2)"))
        #expect(actionSource.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(actionSource.contains(".frame(height: dynamicTypeSize.isAccessibilitySize ? nil : fixedHeight)"))
        #expect(actionSource.contains("dynamicTypeSize.isAccessibilitySize || fixedHeight == nil"))
        #expect(homeActionSource.contains("if store.activeSegments.isEmpty"))
        #expect(homeActionSource.contains(".buttonStyle(.borderedProminent)"))
        #expect(homeActionSource.contains(".buttonStyle(.bordered)"))
        #expect(homeActionSource.contains("home.newTask") == false)
        #expect(inboxSuggestionSource.contains("if isCompact {"))
        #expect(inboxSuggestionSource.contains("ViewThatFits(in: .horizontal)"))
        #expect(readySuggestionSource.contains("ViewThatFits(in: .horizontal)") == false)
        #expect(readySuggestionSource.contains("Text(.app(\"inbox.suggestion.label\"))"))
        #expect(readySuggestionSource.contains("Spacer(minLength: 8)"))
        #expect(readySuggestionSource.contains("systemImage: \"xmark\""))
        #expect(readySuggestionSource.contains("systemImage: \"checkmark\""))
        #expect(readySuggestionSource.contains(".buttonStyle(.bordered)"))
        #expect(readySuggestionSource.contains(".buttonStyle(.borderedProminent)"))
        #expect(readySuggestionSource.contains(".buttonBorderShape(.circle)"))
        #expect(
            readySuggestionSource.contains(
                "width: AppLayout.minimumInteractiveTarget - 14"
            )
        )
        #expect(
            readySuggestionSource.components(
                separatedBy: "width: AppLayout.minimumInteractiveTarget,"
            ).count - 1 == 2
        )
        #expect(
            inboxSuggestionSource.components(
                separatedBy: ".frame(minWidth: 160, alignment: .leading)"
            ).count - 1 == 1
        )
        #expect(inboxSuggestionSource.contains("InboxSuggestionBackground") == false)
        #expect(inboxSuggestionSource.contains("ChecklistItemIcon("))
        #expect(inboxSuggestionSource.contains("style: .solid"))
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
        #expect(inboxSuggestionSource.contains("CompactTextActionLabel("))
        #expect(actionSource.contains("struct CompactTextActionLabel"))
        #expect(
            actionSource.contains(
                "minWidth: AppLayout.minimumInteractiveTarget,\n" +
                    "                minHeight: AppLayout.minimumInteractiveTarget"
            )
        )
        #expect(
            readySuggestionSource.contains(
                "accessibilityLabel: AppStrings.localized(\"inbox.suggestion.apply\")"
            )
        )
        #expect(
            readySuggestionSource.contains(
                "accessibilityLabel: AppStrings.localized(\"inbox.suggestion.discard\")"
            )
        )
        #expect(readySuggestionSource.contains(".accessibilityLabel(accessibilityLabel)"))
    }

    @Test
    func sharedInformationComponentsAdaptAndExposeConciseSemantics() throws {
        let sectionHeader = try sourceText("timetracker/SharedUI/Components/SectionHeaders.swift")
        let emptyState = try sourceText("timetracker/SharedUI/Components/EmptyStates.swift")
        let infoRow = try sourceText("timetracker/SharedUI/Components/InfoRows.swift")
        let forecast = try sourceText("timetracker/SharedUI/Components/ForecastInfoViews.swift")
        let metrics = try sourceText("timetracker/SharedUI/Components/MetricCards.swift")

        #expect(sectionHeader.contains(".accessibilityAddTraits(.isHeader)"))
        #expect(sectionHeader.contains(".accessibilityHidden(true)"))
        #expect(emptyState.contains(".accessibilityElement(children: .ignore)"))
        #expect(emptyState.contains(".accessibilityLabel(title)"))
        #expect(infoRow.contains("ViewThatFits(in: .horizontal)"))
        #expect(infoRow.contains(".fixedSize(horizontal: false, vertical: true)"))
        #expect(forecast.contains("minWidth: AppLayout.minimumInteractiveTarget"))
        #expect(forecast.components(separatedBy: ".accessibilityHidden(true)").count - 1 >= 2)
        #expect(metrics.contains("dynamicTypeSize.isAccessibilitySize ? nil : 1"))
        #expect(metrics.contains(".accessibilityValue(\"\\(metric.value), \\(metric.trendText)\")"))
    }
}
