import SwiftUI

struct TaskCategoryPickerOption: Identifiable, Equatable {
    let id: UUID
    let title: String
    let iconName: String
    let colorHex: String?

    init(
        id: UUID,
        title: String,
        iconName: String,
        colorHex: String? = nil
    ) {
        self.id = id
        self.title = title
        self.iconName = iconName
        self.colorHex = colorHex
    }
}

enum TaskCategoryPickerSelectionContext: Equatable {
    case inboxTaskDestination

    var navigationTitle: String {
        switch self {
        case .inboxTaskDestination:
            AppStrings.localized("inbox.route.categoryTask.title")
        }
    }

    var accessibilityIdentifier: String {
        switch self {
        case .inboxTaskDestination:
            "inbox.categoryTask.categoryPicker"
        }
    }

    var selectionHint: String {
        switch self {
        case .inboxTaskDestination:
            AppStrings.localized("inbox.route.categoryTask.selectionHint")
        }
    }

    var emptyStateTitle: String {
        switch self {
        case .inboxTaskDestination:
            AppStrings.localized("inbox.route.categoryTask.empty")
        }
    }

    var emptyStateDescription: String {
        switch self {
        case .inboxTaskDestination:
            AppStrings.localized("inbox.route.categoryTask.emptyDescription")
        }
    }
}

struct TaskCategoryPicker: View {
    let options: [TaskCategoryPickerOption]
    let selectedCategoryID: UUID?
    let context: TaskCategoryPickerSelectionContext
    let onDismiss: () -> Void
    let onSelect: (UUID) -> Void

    @State private var searchText = ""

    var body: some View {
        Group {
            if displayedOptions.isEmpty {
                emptyState
            } else {
                categoryList
            }
        }
        #if os(iOS)
        .background(Color(uiColor: .systemGroupedBackground))
        .searchable(
            text: $searchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: AppStrings.localized("taskCategory.searchPrompt")
        )
        #else
        .background(AppColors.background)
        .searchable(
            text: $searchText,
            prompt: AppStrings.localized("taskCategory.searchPrompt")
        )
        #endif
        .navigationTitle(context.navigationTitle)
        .accessibilityIdentifier(context.accessibilityIdentifier)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.cancel, action: onDismiss)
            }
        }
    }

    private var categoryList: some View {
        List(displayedOptions) { option in
            Button {
                onSelect(option.id)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: option.iconName)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(
                            Color(hex: option.colorHex) ?? .secondary
                        )
                        .frame(width: 28, alignment: .center)
                        .accessibilityHidden(true)

                    Text(option.title)
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if selectedCategoryID == option.id {
                        Image(systemName: "checkmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: AppLayout.minimumInteractiveTarget,
                    alignment: .leading
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(option.title)
            .accessibilityHint(context.selectionHint)
            .accessibilityAddTraits(
                selectedCategoryID == option.id ? .isSelected : []
            )
            .accessibilityIdentifier(
                "\(context.accessibilityIdentifier).select.\(option.id.uuidString)"
            )
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .scrollContentBackground(.hidden)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label(
                emptyStateTitle,
                systemImage: isSearching ? "magnifyingglass" : "square.grid.2x2"
            )
        } description: {
            Text(emptyStateDescription)
        } actions: {
            if isSearching {
                Button(AppStrings.localized("tasks.search.clear")) {
                    searchText = ""
                }
                .buttonStyle(.borderedProminent)
            }
        }
    }

    private var displayedOptions: [TaskCategoryPickerOption] {
        guard isSearching else { return options }
        return options.filter {
            $0.title.localizedStandardContains(
                searchText.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }

    private var isSearching: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private var emptyStateTitle: String {
        isSearching
            ? AppStrings.localized("taskCategory.search.empty")
            : context.emptyStateTitle
    }

    private var emptyStateDescription: String {
        isSearching
            ? AppStrings.localized("taskCategory.search.emptyDescription")
            : context.emptyStateDescription
    }
}
