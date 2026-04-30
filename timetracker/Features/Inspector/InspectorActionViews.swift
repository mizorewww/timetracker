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
                        Label(AppStrings.edit, systemImage: "pencil")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)

                    Button {
                        store.archiveSelectedTask()
                    } label: {
                        Label(AppStrings.localized("task.action.archive"), systemImage: "archivebox")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }

                Button(role: .destructive) {
                    store.deleteSelectedTask()
                } label: {
                    Label(AppStrings.localized("task.action.softDeleteTask"), systemImage: "trash")
                        .frame(maxWidth: .infinity)
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
                    Label(AppStrings.localized("timer.action.pause"), systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive) {
                    store.stop(segment: segment)
                } label: {
                    Label(AppStrings.localized("timer.action.stop"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else if let session = store.pausedSession(for: task.id) {
            HStack(spacing: 10) {
                Button {
                    store.resume(session: session)
                } label: {
                    Label(AppStrings.localized("timer.action.resume"), systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)

                Button(role: .destructive) {
                    store.stop(session: session)
                } label: {
                    Label(AppStrings.localized("timer.action.end"), systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else {
            Button {
                store.startTask(task)
            } label: {
                Label(AppStrings.localized("task.action.startTimer"), systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
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
                        Label(AppStrings.localized("pomodoro.action.resume"), systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                } else {
                    Button {
                        store.completeActivePomodoro()
                    } label: {
                        Label(AppStrings.localized("pomodoro.action.completeRound"), systemImage: "checkmark.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button(role: .destructive) {
                    store.cancelActivePomodoro()
                } label: {
                    Label(AppStrings.cancel, systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.large)
        } else {
            Button {
                store.startPomodoroForSelectedTask()
            } label: {
                Label(AppStrings.localized("pomodoro.action.start"), systemImage: "timer")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
    }
}
