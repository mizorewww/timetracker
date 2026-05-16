import SwiftUI

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()
    @State private var didExpandInitialTree = false
    @State private var detailTaskID: UUID?

    private var searchResults: [TaskNode] {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        return store.tasks.filter { task in
            task.title.localizedCaseInsensitiveContains(trimmed) ||
            store.path(for: task).localizedCaseInsensitiveContains(trimmed) ||
            (task.notes?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    var body: some View {
        List {
            if searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                ForEach(store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs)) { section in
                    Section {
                        TaskCategorySectionHeader(
                            section: section,
                            addTask: newRootTaskAction(for: section),
                            editCategory: editAction(for: section)
                        )
                        .padding(.vertical, 3)
                        .listRowSeparator(.hidden)
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button(action: newRootTaskAction(for: section)) {
                                Label(AppStrings.localized("tasks.newRoot"), systemImage: "plus")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if let deleteCategory = deleteAction(for: section) {
                                Button(role: .destructive, action: deleteCategory) {
                                    Label(AppStrings.localized("taskCategory.delete"), systemImage: "trash")
                                }
                            }
                        }

                        ForEach(section.rows) { row in
                            if let task = store.task(for: row.taskID) {
                                TaskManagementFlatRow(
                                    store: store,
                                    task: task,
                                    treeDepth: row.depth,
                                    hasChildren: row.hasChildren,
                                    isExpanded: row.isExpanded,
                                    toggleExpansion: {
                                        expansionState.toggle(row.taskID)
                                    },
                                    openTaskDetail: { task in
                                        detailTaskID = task.id
                                    }
                                )
                            }
                        }
                    }
                }
            } else if searchResults.isEmpty {
                EmptyStateRow(title: AppStrings.localized("tasks.empty.search"), icon: "magnifyingglass")
            } else {
                Section(AppStrings.localized("tasks.searchResults")) {
                    ForEach(searchResults, id: \.id) { task in
                        TaskManagementFlatRow(
                            store: store,
                            task: task,
                            openTaskDetail: { task in
                                detailTaskID = task.id
                            }
                        )
                    }
                }
            }

            Section {
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
            }
        }
        .navigationTitle(AppStrings.tasks)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        #if os(iOS)
        .listStyle(.insetGrouped)
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
                Image(systemName: "plus.circle")
            }
        }
        .navigationDestination(isPresented: detailBinding) {
            if let detailTaskID, let task = store.task(for: detailTaskID) {
                TaskDetailView(store: store, taskID: task.id)
            } else {
                EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
            }
        }
        .onAppear {
            if !didExpandInitialTree {
                for task in store.tasks {
                    expansionState.expand(task.id)
                }
                didExpandInitialTree = true
            }
        }
    }

    private var detailBinding: Binding<Bool> {
        Binding {
            detailTaskID != nil
        } set: { isPresented in
            if !isPresented {
                detailTaskID = nil
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
            store.deleteTaskCategory(category)
        }
    }
}
