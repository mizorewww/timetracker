import SwiftUI

struct QuickStartSection: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var isEditorPresented = false

    private var selectedIDs: [UUID] {
        store.preferences.quickStartTaskIDs
    }

    private var pinnedTasks: [TaskNode] {
        selectedIDs.compactMap { store.task(for: $0) }
            .filter { $0.deletedAt == nil && $0.status != .archived }
    }

    private var recentFillTasks: [TaskNode] {
        store.frequentRecentTasks(
            excluding: Set(pinnedTasks.map(\.id)),
            limit: 3
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(AppStrings.quickStart)
                        .font(.headline)
                    Text(AppStrings.localized("quickStart.defaultHint"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    isEditorPresented = true
                } label: {
                    Image(systemName: "slider.horizontal.3")
                }
                .buttonStyle(.bordered)
                .help(AppStrings.localized("quickStart.edit"))
            }

            if pinnedTasks.isEmpty && recentFillTasks.isEmpty {
                ContentUnavailableView(
                    AppStrings.localized("quickStart.empty.title"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(.app("quickStart.empty.description"))
                )
                .frame(maxWidth: .infinity, minHeight: 104)
            } else {
                if !pinnedTasks.isEmpty {
                    QuickStartTaskGroup(
                        title: AppStrings.localized("quickStart.pinnedTasks"),
                        tasks: pinnedTasks,
                        store: store
                    )
                }

                if !recentFillTasks.isEmpty {
                    QuickStartTaskGroup(
                        title: AppStrings.localized("quickStart.recentTasks"),
                        tasks: recentFillTasks,
                        store: store
                    )
                }
            }
        }
        .sheet(isPresented: $isEditorPresented) {
            QuickStartEditorSheet(
                store: store,
                selectedIDs: selectedIDs,
                onSave: { ids in
                    store.setQuickStartTaskIDs(ids)
                }
            )
        }
    }
}
