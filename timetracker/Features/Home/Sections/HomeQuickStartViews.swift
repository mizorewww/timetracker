import SwiftUI

struct QuickStartSection: View {
    let store: TimeTrackerStore
    let tasks: [TaskNode]
    @State private var isEditorPresented = false

    private var selectedIDs: [UUID] {
        store.preferences.quickStartTaskIDs
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
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel(AppStrings.localized("quickStart.edit"))
                .accessibilityIdentifier("home.quickStart.edit")
                .help(AppStrings.localized("quickStart.edit"))
            }

            if tasks.isEmpty {
                ContentUnavailableView(
                    AppStrings.localized("quickStart.empty.title"),
                    systemImage: "clock.arrow.circlepath",
                    description: Text(.app("quickStart.empty.description"))
                )
                .frame(maxWidth: .infinity, minHeight: 104)
            } else {
                QuickStartTaskGroup(tasks: tasks, store: store)
            }
        }
        .accessibilityIdentifier("home.quickStart")
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
