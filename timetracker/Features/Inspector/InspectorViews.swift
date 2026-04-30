import SwiftUI

struct InspectorView: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(.app("inspector.selectedTask"))
                    .font(.headline)

                if let task = store.selectedTask {
                    SelectedTaskHeader(store: store, task: task)
                    InspectorInfoGrid(store: store, task: task)
                    TaskChecklistPanel(store: store, task: task)
                    if !store.children(of: task).isEmpty {
                        TaskForecastPanel(store: store, task: task)
                    }
                    NotesPanel(task: task)
                    StatsPanel(store: store, task: task)
                    PomodoroSettingsPanel(store: store)
                    RecentSessionsPanel(store: store, task: task)
                    InspectorActionButtons(store: store)
                } else {
                    EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
                }
            }
            .padding(20)
        }
        .background(AppColors.background)
    }
}

struct SelectedTaskHeader: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    @State private var isPulsing = false

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(Color(hex: task.colorHex) ?? .blue)
                .frame(width: 10, height: 10)
            Text(task.title)
                .font(.title3.weight(.semibold))
                .lineLimit(2)
            Spacer()
            Button {
                store.presentEditTask(task)
            } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
        }
        .scaleEffect(isPulsing ? 1.045 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isPulsing)
        .onChange(of: store.selectedTaskPulseToken) { _, _ in
            guard store.selectedTaskPulseID == task.id else { return }
            isPulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                isPulsing = false
            }
        }
    }
}
