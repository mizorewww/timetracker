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
            HStack(spacing: 10) {
                Button {
                    store.pause(segment: segment)
                } label: {
                    AppActionLabel(title: AppStrings.localized("timer.action.pause"), systemImage: "pause.fill")
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    store.stop(segment: segment)
                } label: {
                    AppActionLabel(title: AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else if let session = store.pausedSession(for: task.id) {
            HStack(spacing: 10) {
                Button {
                    store.resume(session: session)
                } label: {
                    AppActionLabel(title: AppStrings.localized("timer.action.resume"), systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    store.stop(session: session)
                } label: {
                    AppActionLabel(title: AppStrings.localized("timer.action.end"), systemImage: "stop.fill")
                }
                .buttonStyle(.bordered)
            }
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
        if let run = store.activePomodoroRun(for: task.id) {
            HStack(spacing: 10) {
                if run.state == .interrupted,
                   let sessionID = run.sessionID,
                   let session = store.sessions.first(where: { $0.id == sessionID }) {
                    Button {
                        store.resume(session: session)
                    } label: {
                        AppActionLabel(title: AppStrings.localized("pomodoro.action.resume"), systemImage: "play.fill")
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        store.completeActivePomodoro()
                    } label: {
                        AppActionLabel(title: AppStrings.localized("pomodoro.action.completeRound"), systemImage: "checkmark.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }

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
