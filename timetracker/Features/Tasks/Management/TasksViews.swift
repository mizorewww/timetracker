import SwiftUI

struct TasksView: View {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()
    @State private var categoryExpansionState = TaskCategoryExpansionState()
    @State private var categoryPendingDeletionID: UUID?
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingTasks = query.isEmpty ? [] : store.taskSearchResults(matching: query)
        let rowSupplements = TaskManagementRowSupplementProjection(
            store: store
        )

        List {
            TaskRecoveryDraftsSection(store: store)

            #if os(iOS)
            if usesInlineSearchField {
                Section {
                    TextField(AppStrings.localized("tasks.searchTitle"), text: $searchText)
                        .textFieldStyle(.roundedBorder)
                        .submitLabel(.search)
                        .accessibilityLabel(AppStrings.localized("tasks.searchTitle"))
                        .accessibilityHint(AppStrings.localized("tasks.searchHint"))
                        .accessibilityIdentifier("tasks.search.field")
                        .padding(.vertical, 2)
                }
            }
            #endif

            if query.isEmpty {
                if store.visibleTaskCount == 0 {
                    ContentUnavailableView {
                        Label(AppStrings.localized("tasks.empty.title"), systemImage: "checklist")
                    } description: {
                        Text(.app("tasks.empty.description"))
                    } actions: {
                        Button(AppStrings.localized("tasks.newRoot")) {
                            presentationRouter.presentNewTask(using: store, preservingDestination: .tasks)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(
                    store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs)
                ) { section in
                    taskCategorySection(
                        section,
                        rowSupplements: rowSupplements
                    )
                }
            } else if matchingTasks.isEmpty {
                ContentUnavailableView.search(text: query)
                    .listRowBackground(Color.clear)
            } else {
                Section(AppStrings.localized("tasks.searchResults")) {
                    ForEach(matchingTasks, id: \.id) { task in
                        TaskManagementFlatRow(
                            store: store,
                            task: task,
                            supplement: rowSupplements.supplement(
                                for: task.id
                            ),
                            childCount: store.visibleChildCount(for: task.id),
                            identityContext: .standard,
                            openTaskDetail: { task in
                                store.openTaskDetail(task.id)
                            }
                        )
                    }
                }
            }

        }
        .modifier(
            TasksSearchPresentation(
                text: $searchText,
                usesInlineField: usesInlineSearchField
            )
        )
        .navigationTitle(AppStrings.tasks)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .accessibilityIdentifier("tasks.view")
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        #else
        .listStyle(.inset)
        #endif
        .toolbar {
            Menu {
                Button {
                    presentationRouter.presentNewTask(using: store, preservingDestination: .tasks)
                } label: {
                    Label(AppStrings.localized("tasks.newRoot"), systemImage: "plus")
                }
                .accessibilityIdentifier("tasks.addRoot")

                Button {
                    presentationRouter.presentNewTaskCategory()
                } label: {
                    Label(AppStrings.localized("taskCategory.new"), systemImage: "square.grid.2x2")
                }

                Button {
                    presentationRouter.presentTaskCategoryOrdering()
                } label: {
                    Label(
                        AppStrings.localized("taskCategory.sort"),
                        systemImage: "arrow.up.arrow.down"
                    )
                }
                .disabled(store.taskCategories.count < 2)
                .accessibilityIdentifier("tasks.sortCategories")

                Divider()

                Button {
                    presentationRouter.presentAITaskPlanGenerator()
                } label: {
                    Label(
                        AppStrings.localized("aiTaskPlan.generateMenu"),
                        systemImage: "sparkles"
                    )
                }
                .accessibilityIdentifier("tasks.generatePlan")
            } label: {
                Label(AppStrings.localized("tasks.add"), systemImage: "plus")
            }
            .accessibilityIdentifier("tasks.add")
        }
        .confirmationDialog(
            AppStrings.localized("taskCategory.delete.confirm.title"),
            isPresented: categoryDeletionBinding,
            titleVisibility: .visible
        ) {
            Button(AppStrings.localized("taskCategory.delete"), role: .destructive) {
                if let categoryPendingDeletionID,
                   let category = store.taskCategory(for: categoryPendingDeletionID) {
                    store.deleteTaskCategory(category)
                }
                categoryPendingDeletionID = nil
            }
            Button(AppStrings.cancel, role: .cancel) {
                categoryPendingDeletionID = nil
            }
        } message: {
            Text(.app("taskCategory.delete.confirm.message"))
        }
    }

    @ViewBuilder
    private func taskCategorySection(
        _ section: TaskTreeVisibleSectionModel,
        rowSupplements: TaskManagementRowSupplementProjection
    ) -> some View {
        if section.rows.isEmpty {
            Section {
                taskCategoryRows(
                    section,
                    rowSupplements: rowSupplements
                )
            } header: {
                TaskCategorySectionHeader(
                    section: section,
                    addTask: newRootTaskAction(for: section),
                    editCategory: editAction(for: section),
                    deleteCategory: deleteAction(for: section)
                )
            }
        } else {
            let isExpanded = categoryExpansionState.isExpanded(section.id)
            Section(
                isExpanded: categoryExpansionBinding(for: section.id)
            ) {
                taskCategoryRows(
                    section,
                    rowSupplements: rowSupplements
                )
            } header: {
                TaskCategorySectionHeader(
                    section: section,
                    addTask: newRootTaskAction(for: section),
                    editCategory: editAction(for: section),
                    deleteCategory: deleteAction(for: section),
                    isExpanded: isExpanded,
                    toggleExpansion: {
                        categoryExpansionState.toggle(section.id)
                    },
                    disclosureAccessibilityIdentifier:
                        "tasks.category.disclosure.\(section.id)"
                )
            }
        }
    }

    private func taskCategoryRows(
        _ section: TaskTreeVisibleSectionModel,
        rowSupplements: TaskManagementRowSupplementProjection
    ) -> some View {
        ForEach(section.rows) { row in
            TaskManagementTreeRow(
                store: store,
                row: row,
                supplement: rowSupplements.supplement(for: row.taskID),
                toggleExpansion: {
                    expansionState.toggle(row.taskID)
                },
                openTaskDetail: { task in
                    store.openTaskDetail(task.id)
                }
            )
        }
    }

    private func categoryExpansionBinding(
        for sectionID: String
    ) -> Binding<Bool> {
        Binding {
            categoryExpansionState.isExpanded(sectionID)
        } set: { isExpanded in
            categoryExpansionState.setExpanded(
                isExpanded,
                for: sectionID
            )
        }
    }

    private var categoryDeletionBinding: Binding<Bool> {
        Binding {
            categoryPendingDeletionID != nil
        } set: { isPresented in
            if !isPresented {
                categoryPendingDeletionID = nil
            }
        }
    }

    private var usesInlineSearchField: Bool {
        #if os(iOS)
        dynamicTypeSize.isAccessibilitySize
        #else
        false
        #endif
    }

    private func newRootTaskAction(for section: TaskTreeVisibleSectionModel) -> () -> Void {
        {
            presentationRouter.presentNewTask(
                using: store,
                preservingDestination: .tasks,
                categoryID: section.categoryID
            )
        }
    }

    private func editAction(for section: TaskTreeVisibleSectionModel) -> (() -> Void)? {
        guard let categoryID = section.categoryID,
              let category = store.taskCategory(for: categoryID) else {
            return nil
        }
        return {
            presentationRouter.presentEditTaskCategory(category)
        }
    }

    private func deleteAction(for section: TaskTreeVisibleSectionModel) -> (() -> Void)? {
        guard let categoryID = section.categoryID,
              let category = store.taskCategory(for: categoryID) else {
            return nil
        }
        return {
            categoryPendingDeletionID = category.id
        }
    }
}

private struct TasksSearchPresentation: ViewModifier {
    @Binding var text: String
    let usesInlineField: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if usesInlineField {
            content
        } else {
            content.searchable(
                text: $text,
                prompt: AppStrings.localized("tasks.searchPrompt")
            )
        }
    }
}

private struct TaskManagementTreeRow: View {
    let store: TimeTrackerStore
    let row: TaskTreeRowModel
    let supplement: TaskManagementRowSupplement
    let toggleExpansion: () -> Void
    let openTaskDetail: (TaskNode) -> Void

    var body: some View {
        Group {
            if let task = store.task(for: row.taskID) {
                TaskManagementFlatRow(
                    store: store,
                    task: task,
                    supplement: supplement,
                    treeDepth: row.depth,
                    childCount: row.childCount,
                    isExpanded: row.isExpanded,
                    toggleExpansion: toggleExpansion,
                    openTaskDetail: openTaskDetail
                )
            } else {
                EmptyView()
            }
        }
    }
}
