import SwiftUI

struct TasksView: View {
    let store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()
    @State private var detailTaskID: UUID?
    @State private var categoryPendingDeletionID: UUID?

    private func searchResults(matching query: String) -> [TaskNode] {
        return store.tasks.filter { task in
            store.isTaskVisible(task) && (
                task.title.localizedCaseInsensitiveContains(query) ||
                store.path(for: task).localizedCaseInsensitiveContains(query) ||
                (task.notes?.localizedCaseInsensitiveContains(query) ?? false)
            )
        }
    }

    var body: some View {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        let matchingTasks = query.isEmpty ? [] : searchResults(matching: query)

        List {
            if query.isEmpty {
                if !store.tasks.contains(where: store.isTaskVisible) {
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
                            openTaskDetail: { task in
                                store.openTaskDetail(task.id)
                                detailTaskID = task.id
                            }
                        )
                    }
                }
            }

        }
        .navigationTitle(AppStrings.tasks)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
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

                Button {
                    store.presentNewTaskCategory()
                } label: {
                    Label(AppStrings.localized("taskCategory.new"), systemImage: "square.grid.2x2")
                }
            } label: {
                Label(AppStrings.localized("tasks.add"), systemImage: "plus")
            }
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
                    hasChildren: row.hasChildren,
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
