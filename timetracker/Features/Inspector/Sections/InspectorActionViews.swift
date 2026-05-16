import SwiftUI

struct InspectorActionButtons: View {
    @ObservedObject var store: TimeTrackerStore

    var body: some View {
        if let task = store.selectedTask {
            VStack(spacing: 10) {
                timerControls(for: task)
                pomodoroControls(for: task)

                HStack(spacing: 10) {
                    Button {
                        store.presentEditTask(task)
                    } label: {
                        AppActionLabel(title: AppStrings.edit, systemImage: "pencil")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.archiveSelectedTask()
                    } label: {
                        AppActionLabel(title: AppStrings.localized("task.action.archive"), systemImage: "archivebox")
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    store.deleteSelectedTask()
                } label: {
                    AppActionLabel(title: AppStrings.localized("task.action.softDeleteTask"), systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
        }
    }

    @ViewBuilder
    private func timerControls(for task: TaskNode) -> some View {
        if let segment = store.activeSegment(for: task.id) {
            Button(role: .destructive) {
                store.stop(segment: segment)
            } label: {
                AppActionLabel(title: AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        } else {
            Button {
                store.startTask(task)
            } label: {
                AppActionLabel(title: AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }

    @ViewBuilder
    private func pomodoroControls(for task: TaskNode) -> some View {
        if store.activePomodoroRun(for: task.id) != nil {
            HStack(spacing: 10) {
                Button {
                    store.completeActivePomodoro()
                } label: {
                    AppActionLabel(title: AppStrings.localized("pomodoro.action.completeRound"), systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    store.cancelActivePomodoro()
                } label: {
                    AppActionLabel(title: AppStrings.cancel, systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else {
            Button {
                store.startPomodoroForSelectedTask()
            } label: {
                AppActionLabel(title: AppStrings.localized("pomodoro.action.start"), systemImage: "timer")
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
