import SwiftUI
#if os(iOS)
import UIKit
#endif

struct ActionStack: View {
    @ObservedObject var store: TimeTrackerStore
    var buttonHeight: CGFloat?
    var spacing: CGFloat = 12
#if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var isTaskPickerPresented = false

    private var isCompactPhone: Bool {
        SizeClassLayoutPolicy(horizontalSizeClass: horizontalSizeClass).isCompactPhone
    }
#endif

    var body: some View {
        actionLayout
#if os(iOS)
        .sheet(isPresented: $isTaskPickerPresented) {
            NavigationStack {
                TaskStartPicker(store: store) {
                    isTaskPickerPresented = false
                }
            }
            .presentationDetents([.medium, .large])
            .presentationBackground(Color(uiColor: .systemGroupedBackground))
        }
#endif
    }

    @ViewBuilder
    private var actionLayout: some View {
#if os(iOS)
        if isCompactPhone {
            HStack(spacing: spacing) {
                startButton
                    .frame(maxWidth: .infinity)
                newTaskButton
                    .frame(maxWidth: .infinity)
            }
        } else {
            VStack(spacing: spacing) {
                startButton
                newTaskButton
            }
        }
#else
        VStack(spacing: spacing) {
            startButton
            newTaskButton
        }
#endif
    }

    private var startButton: some View {
        Button {
#if os(iOS)
            if isCompactPhone {
                isTaskPickerPresented = true
            } else {
                store.startSelectedTask()
            }
#else
            store.startSelectedTask()
#endif
        } label: {
            actionLabel(title: AppStrings.startTimer, systemImage: "play.fill")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.regular)
        .accessibilityIdentifier("home.startTimer")
    }

    private var newTaskButton: some View {
        Button {
            store.presentNewTask()
        } label: {
            actionLabel(title: AppStrings.newTask, systemImage: "plus")
        }
        .buttonStyle(.bordered)
        .controlSize(.regular)
        .accessibilityIdentifier("home.newTask")
    }

    private func actionLabel(title: String, systemImage: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
            Text(title)
                .font(.body.weight(.medium))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
        }
        .frame(maxWidth: .infinity)
        .frame(height: buttonHeight)
        .frame(minHeight: buttonHeight == nil ? 44 : 0)
    }
}

#if os(iOS)
struct TaskStartPicker: View {
    @ObservedObject var store: TimeTrackerStore
    let onDone: () -> Void

    private var availableTasks: [TaskNode] {
        store.tasks.filter { $0.deletedAt == nil && $0.status != .archived }
    }

    var body: some View {
        List {
            Section {
                ForEach(availableTasks, id: \.id) { task in
                    Button {
                        store.startTask(task)
                        onDone()
                    } label: {
                        TaskStartPickerRow(
                            task: task,
                            path: store.path(for: task),
                            isRunning: store.activeSegment(for: task.id) != nil
                        )
                    }
                }
            } header: {
                Text(.app("timer.chooseTaskHeader"))
            } footer: {
                Text(.app("timer.chooseTaskFooter"))
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(AppStrings.startTimer)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(AppStrings.cancel, action: onDone)
            }
        }
    }
}

private struct TaskStartPickerRow: View {
    let task: TaskNode
    let path: String
    let isRunning: Bool

    var body: some View {
        HStack(spacing: 12) {
            TaskIcon(task: task, size: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(task.title)
                    .foregroundStyle(.primary)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isRunning {
                RunningStatusBadge()
            }
        }
    }
}
#endif
