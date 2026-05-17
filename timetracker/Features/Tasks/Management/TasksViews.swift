import SwiftUI
#if os(iOS)
import UIKit
#endif

struct TasksView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var searchText = ""
    @State private var expansionState = TaskExpansionState()
    @State private var didExpandInitialTree = false
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

                SystemSearchBar(text: $searchText, placeholder: AppStrings.localized("tasks.searchPrompt"))
                    .frame(height: 44)
                    .padding(.horizontal, PhoneRootChromeMetrics.groupedSearchHorizontalAdjustment)
                    .listRowInsets(PhoneRootChromeMetrics.groupedSearchRowInsets)
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

                Button {
                    store.presentNewTaskCategory()
                } label: {
                    Label(AppStrings.localized("taskCategory.new"), systemImage: "square.grid.2x2")
                }
            } label: {
                Image(systemName: "plus.circle")
            }
        }
        #if os(iOS)
        .phoneChromeScrollObserver(destination: .tasks, enabled: isCompactPhone)
        .phoneRootChrome(destination: .tasks, enabled: isCompactPhone)
        #endif
        .navigationDestination(isPresented: detailBinding) {
            if let detailTaskID, let task = store.task(for: detailTaskID) {
                TaskDetailView(store: store, taskID: task.id)
                    #if os(iOS)
                    .phoneSecondaryDestination(.tasks)
                    #endif
            } else {
                EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
                    #if os(iOS)
                    .phoneSecondaryDestination(.tasks)
                    #endif
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

private struct TaskSearchPlacementModifier: ViewModifier {
    @Binding var searchText: String
    let isCompactPhone: Bool

    func body(content: Content) -> some View {
        #if os(iOS)
        if isCompactPhone {
            content
        } else {
            content.searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        }
        #else
        content.searchable(text: $searchText, prompt: AppStrings.localized("tasks.searchPrompt"))
        #endif
    }
}

#if os(iOS)
private struct SystemSearchBar: UIViewRepresentable {
    @Binding var text: String
    let placeholder: String

    func makeUIView(context: Context) -> UISearchBar {
        let searchBar = UISearchBar(frame: .zero)
        searchBar.searchBarStyle = .minimal
        searchBar.backgroundColor = .clear
        searchBar.backgroundImage = UIImage()
        searchBar.setBackgroundImage(UIImage(), for: .any, barMetrics: .default)
        searchBar.isTranslucent = true
        searchBar.layer.shadowOpacity = 0
        searchBar.placeholder = placeholder
        searchBar.autocapitalizationType = .none
        searchBar.autocorrectionType = .no
        searchBar.returnKeyType = .done
        searchBar.enablesReturnKeyAutomatically = false
        searchBar.delegate = context.coordinator
        searchBar.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        configureSearchTextField(searchBar.searchTextField)
        return searchBar
    }

    func updateUIView(_ searchBar: UISearchBar, context: Context) {
        searchBar.backgroundColor = .clear
        searchBar.backgroundImage = UIImage()
        searchBar.setBackgroundImage(UIImage(), for: .any, barMetrics: .default)
        configureSearchTextField(searchBar.searchTextField)
        if searchBar.text != text {
            searchBar.text = text
        }
        if searchBar.placeholder != placeholder {
            searchBar.placeholder = placeholder
        }
        let shouldShowCancel = searchBar.isFirstResponder || !text.isEmpty
        if searchBar.showsCancelButton != shouldShowCancel {
            searchBar.setShowsCancelButton(shouldShowCancel, animated: false)
        }
    }

    private func configureSearchTextField(_ textField: UISearchTextField) {
        textField.backgroundColor = .secondarySystemGroupedBackground
        textField.borderStyle = .none
        textField.layer.cornerCurve = .continuous
        textField.layer.cornerRadius = 16
        textField.layer.masksToBounds = true
        textField.layer.shadowOpacity = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    final class Coordinator: NSObject, UISearchBarDelegate {
        @Binding private var text: String

        init(text: Binding<String>) {
            _text = text
        }

        func searchBar(_ searchBar: UISearchBar, textDidChange searchText: String) {
            text = searchText
        }

        func searchBarTextDidBeginEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(true, animated: true)
        }

        func searchBarTextDidEndEditing(_ searchBar: UISearchBar) {
            searchBar.setShowsCancelButton(!text.isEmpty, animated: true)
        }

        func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
            searchBar.resignFirstResponder()
        }

        func searchBarCancelButtonClicked(_ searchBar: UISearchBar) {
            text = ""
            searchBar.text = ""
            searchBar.setShowsCancelButton(false, animated: true)
            searchBar.resignFirstResponder()
        }
    }
}
#endif
