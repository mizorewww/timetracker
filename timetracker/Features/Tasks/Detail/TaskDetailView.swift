import Combine
import SwiftUI

struct TaskDetailView: View {
    @ObservedObject var store: TimeTrackerStore
    let taskID: UUID
    @State private var range: AnalyticsRange = .week
    @State private var now = Date()
    @State private var draft: TaskEditorDraft?
    @State private var isEditorExpanded = false
    @FocusState private var focusedChecklistDraftID: UUID?
    private let refreshTimer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()

    var body: some View {
        Group {
            if let task = store.task(for: taskID) {
                detailContent(task: task)
            } else {
                EmptyStateRow(title: AppStrings.localized("task.empty.selectTask"), icon: "cursorarrow.click")
            }
        }
        .navigationTitle(store.task(for: taskID)?.title ?? AppStrings.localized("task.detail.title"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .onReceive(refreshTimer) { date in
            now = date
        }
    }

    private func detailContent(task: TaskNode) -> some View {
        let snapshot = store.taskAnalyticsSnapshot(for: task, range: range, now: now)
        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                TaskDetailHeader(
                    store: store,
                    task: task,
                    snapshot: snapshot,
                    edit: { isEditorExpanded = true }
                )
                TaskDetailOverviewGrid(snapshot: snapshot)
                TaskDetailEditorCard(
                    store: store,
                    draft: detailDraftBinding(for: task),
                    isExpanded: $isEditorExpanded,
                    save: saveDraft,
                    reset: { resetDraft(for: task) },
                    focusedChecklistDraftID: $focusedChecklistDraftID
                )
                TaskForecastPanel(store: store, task: task)
                TaskDetailAnalysisSection(range: $range, snapshot: snapshot)
                TaskDetailRecentRecordsCard(records: snapshot.recentRecords)
            }
            .padding()
        }
        .background(AppColors.background)
        .onAppear {
            loadDraftIfNeeded(for: task)
        }
        .onChange(of: task.id) { _, _ in
            resetDraft(for: task)
        }
    }

    private func detailDraftBinding(for task: TaskNode) -> Binding<TaskEditorDraft> {
        Binding {
            if let draft, draft.taskID == task.id {
                return draft
            }
            return store.editorDraft(for: task)
        } set: { newValue in
            draft = newValue
        }
    }

    private func loadDraftIfNeeded(for task: TaskNode) {
        guard draft?.taskID != task.id else { return }
        draft = store.editorDraft(for: task)
    }

    private func resetDraft(for task: TaskNode) {
        draft = store.editorDraft(for: task)
    }

    private func saveDraft() {
        let draftToSave: TaskEditorDraft
        if let draft {
            draftToSave = draft
        } else if let task = store.task(for: taskID) {
            draftToSave = store.editorDraft(for: task)
        } else {
            return
        }

        if store.saveTaskDraft(draftToSave),
           let refreshedTask = store.task(for: taskID) {
            self.draft = store.editorDraft(for: refreshedTask)
        }
    }
}
