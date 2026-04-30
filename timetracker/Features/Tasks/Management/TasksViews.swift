import SwiftUI

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()
    @State private var didExpandInitialTree = false

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
                Section {
                    ForEach(store.taskTreeRows(expandedTaskIDs: expansionState.expandedTaskIDs)) { row in
                        if let task = store.task(for: row.taskID) {
                            TaskManagementFlatRow(
                                store: store,
                                task: task,
                                treeDepth: row.depth,
                                hasChildren: row.hasChildren,
                                isExpanded: row.isExpanded,
                                toggleExpansion: {
                                    expansionState.toggle(row.taskID)
                                }
                            )
                        }
                    }
                } header: {
                    Text(.app("tasks.tree"))
                } footer: {
                    Text(.app("tasks.tree.footer"))
                }
            } else if searchResults.isEmpty {
                EmptyStateRow(title: AppStrings.localized("tasks.empty.search"), icon: "magnifyingglass")
            } else {
                Section(AppStrings.localized("tasks.searchResults")) {
                    ForEach(searchResults, id: \.id) { task in
                        TaskManagementFlatRow(store: store, task: task)
                    }
                }
            }

            Section {
                Button {
                    store.presentNewTask(preservingDestination: .tasks)
                } label: {
                    Label(AppStrings.localized("tasks.newRoot"), systemImage: "plus")
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
        .transaction { transaction in
            transaction.animation = nil
        }
        .toolbar {
            Button {
                store.presentNewTask(preservingDestination: .tasks)
            } label: {
                Image(systemName: "plus")
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
}
