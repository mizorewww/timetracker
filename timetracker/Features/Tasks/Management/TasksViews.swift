import SwiftUI

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()
    @State private var didExpandInitialTree = false
    private let initialExpansionPolicy = TaskInitialExpansionPolicy()
    @State private var detailTaskID: UUID?
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    private var isCompactPhone: Bool {
        #if os(iOS)
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
        #else
        false
        #endif
    }
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
            #if os(iOS)
            if isCompactPhone {
                PhoneLargePageHeader(destination: .tasks)
                    .listRowInsets(PhoneRootChromeMetrics.groupedHeaderRowInsets)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            #endif
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
                        .swipeActions(edge: .leading, allowsFullSwipe: true) {
                            Button(action: newRootTaskAction(for: section)) {
                                Image(systemName: "plus")
                            }
                            .accessibilityLabel(AppStrings.localized("tasks.newRoot"))
                            .tint(.blue)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            if let deleteCategory = deleteAction(for: section) {
                                Button(role: .destructive, action: deleteCategory) {
                                    Image(systemName: "trash")
                                }
                                .accessibilityLabel(AppStrings.localized("taskCategory.delete"))
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
            #if os(iOS)
            if isCompactPhone {
                PhoneRootListBottomClearanceRow()
            }
            #endif
        }
        .navigationTitle(AppStrings.tasks)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .modifier(TaskSearchPlacementModifier(searchText: $searchText, isCompactPhone: isCompactPhone))
        #if os(iOS)
        .listStyle(.insetGrouped)
        .scrollDismissesKeyboard(.interactively)
        .phoneRootScrollMargins(enabled: isCompactPhone)
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
                .accessibilityIdentifier("tasks.addCategory")
            } label: {
                Image(systemName: "plus.circle")
            }
            .accessibilityIdentifier("tasks.addMenu")
        }
        .accessibilityIdentifier("tasks.view")
        #if os(iOS)
        .phoneChromeScrollObserver(destination: .tasks, enabled: isCompactPhone)
        .phoneRootChrome(destination: .tasks, enabled: isCompactPhone)
        #endif
        .navigationDestination(isPresented: detailBinding) {
            if let detailTaskID, let task = store.task(for: detailTaskID) {
                TaskDetailView(store: store, taskID: task.id)
                    #if os(iOS)
                    .phoneSecondaryDestination(.tasks, enabled: isCompactPhone)
                    #endif
            } else {
                EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
                    #if os(iOS)
                    .phoneSecondaryDestination(.tasks, enabled: isCompactPhone)
                    #endif
            }
        }
        .onAppear {
            if !didExpandInitialTree {
                expansionState.replace(with: initialExpansionPolicy.expandedTaskIDs(for: store.tasks))
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
