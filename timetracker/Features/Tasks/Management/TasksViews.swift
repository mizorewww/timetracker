import SwiftUI

struct TasksView: View {
    let store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()
    @State private var detailTaskID: UUID?
    @State private var categoryPendingDeletionID: UUID?
    #if os(iOS)
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    #endif

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingTasks = query.isEmpty ? [] : store.taskSearchResults(matching: query)

        List {
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
                            store.presentNewTask(preservingDestination: .tasks)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .listRowBackground(Color.clear)
                }

                ForEach(store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs)) { section in
                    Section {
                        ForEach(section.rows) { row in
                            TaskManagementTreeRow(
                                store: store,
                                row: row,
                                toggleExpansion: {
                                    expansionState.toggle(row.taskID)
                                },
                                openTaskDetail: { task in
                                    store.openTaskDetail(task.id)
                                    detailTaskID = task.id
                                }
                            )
                        }
                    } header: {
                        TaskCategorySectionHeader(
                            section: section,
                            addTask: newRootTaskAction(for: section),
                            editCategory: editAction(for: section),
                            deleteCategory: deleteAction(for: section)
                        )
                    }
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
                            childCount: store.visibleChildCount(for: task.id),
                            openTaskDetail: { task in
                                store.openTaskDetail(task.id)
                                detailTaskID = task.id
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
                    store.presentNewTask(preservingDestination: .tasks)
                } label: {
                    Label(AppStrings.localized("tasks.newRoot"), systemImage: "plus")
                }
                .accessibilityIdentifier("tasks.addRoot")

                Button {
                    store.presentNewTaskCategory()
                } label: {
                    Label(AppStrings.localized("taskCategory.new"), systemImage: "square.grid.2x2")
                }
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
        .navigationDestination(isPresented: detailBinding) {
            if let detailTaskID, let task = store.task(for: detailTaskID) {
                TaskDetailView(store: store, taskID: task.id)
            } else {
                EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
            }
        }
        .onAppear {
            if let requestedTaskID = store.desktopTaskDetailID,
               store.task(for: requestedTaskID) != nil {
                detailTaskID = requestedTaskID
            }
        }
        .onChange(of: store.desktopTaskDetailID) { _, requestedTaskID in
            guard let requestedTaskID, store.task(for: requestedTaskID) != nil else { return }
            detailTaskID = requestedTaskID
        }
    }

    private var detailBinding: Binding<Bool> {
        Binding {
            detailTaskID != nil
        } set: { isPresented in
            if !isPresented {
                detailTaskID = nil
                store.closeTaskDetailNavigation()
            }
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
            store.presentNewTask(
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
            store.presentEditTaskCategory(category)
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
    let toggleExpansion: () -> Void
    let openTaskDetail: (TaskNode) -> Void

    var body: some View {
        Group {
            if let task = store.task(for: row.taskID) {
                TaskManagementFlatRow(
                    store: store,
                    task: task,
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
