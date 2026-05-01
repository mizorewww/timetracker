import SwiftUI

enum SidebarSelection: Hashable {
    case destination(TimeTrackerStore.DesktopDestination)
    case task(UUID)
}

struct SidebarView: View {
    @ObservedObject var store: TimeTrackerStore
    @State private var selection: SidebarSelection?
    @State private var expansionState = TaskExpansionState()
    @State private var isSyncingSelection = false

    private var destinations: [TimeTrackerStore.DesktopDestination] {
        #if os(macOS)
        return TimeTrackerStore.DesktopDestination.allCases.filter { $0 != .settings }
        #else
        return TimeTrackerStore.DesktopDestination.allCases
        #endif
    }

    var body: some View {
        List(selection: $selection) {
            Section {
                ForEach(destinations) { destination in
                    SidebarDestinationLabel(destination: destination, count: count(for: destination))
                        .tag(SidebarSelection.destination(destination))
                        .accessibilityIdentifier("sidebar.\(destination.rawValue)")
                }
            }

            ForEach(store.taskTreeSections(expandedTaskIDs: expansionState.expandedTaskIDs)) { section in
                Section {
                    ForEach(section.rows) { row in
                        if let task = store.task(for: row.taskID) {
                            SidebarTaskTreeRow(store: store, task: task, row: row, expansionState: $expansionState)
                                .tag(SidebarSelection.task(task.id))
                        }
                    }
                } header: {
                    TaskCategorySectionHeader(section: section, compact: true, showsBottomDivider: true)
                }
            }

        }
        .navigationTitle(AppStrings.localized("app.name"))
        .onAppear {
            syncSelectionFromStore()
        }
        .onChange(of: selection) { _, newValue in
            guard !isSyncingSelection else { return }
            guard let newValue else { return }
            switch newValue {
            case let .destination(destination):
                store.desktopDestination = destination
            case let .task(taskID):
                store.selectTask(taskID)
            }
        }
        .onChange(of: store.selectedTaskID) { _, _ in
            syncSelectionFromStore()
        }
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                SettingsLink {
                    Image(systemName: "gearshape")
                }
                .accessibilityIdentifier("settings.open")
                .help(AppStrings.settings)
            }
        }
        #endif
    }

    private func syncSelectionFromStore() {
        isSyncingSelection = true
        defer {
            DispatchQueue.main.async {
                isSyncingSelection = false
            }
        }
        if let selectedTaskID = store.selectedTaskID {
            for ancestorID in store.ancestorTaskIDs(for: selectedTaskID) {
                expansionState.expand(ancestorID)
            }
            selection = .task(selectedTaskID)
        } else {
            selection = .destination(store.desktopDestination)
        }
    }

    private func count(for destination: TimeTrackerStore.DesktopDestination) -> Int? {
        switch destination {
        case .today:
            return store.activeSegments.count
        case .inbox:
            return store.openInboxItems.count
        case .tasks:
            return store.tasks.count
        case .pomodoro:
            return store.pomodoroRuns.filter { $0.state == .completed }.count
        case .analytics:
            return nil
        case .settings:
            return nil
        }
    }
}

struct SidebarTaskTreeRow: View {
    @ObservedObject var store: TimeTrackerStore
    let task: TaskNode
    let row: TaskTreeRowModel
    @Binding var expansionState: TaskExpansionState
    @State private var isPulsing = false

    var body: some View {
        taskLabel
    }

    private var taskLabel: some View {
        HStack(spacing: 8) {
            Color.clear
                .frame(width: CGFloat(row.depth) * 14)

            if row.hasChildren {
                Button {
                    expansionState.toggle(task.id)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .rotationEffect(.degrees(row.isExpanded ? 90 : 0))
                        .foregroundStyle(.secondary)
                        .frame(width: 14, height: 18)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(row.isExpanded ? AppStrings.localized("task.tree.collapse") : AppStrings.localized("task.tree.expand"))
            } else {
                Color.clear
                    .frame(width: 14, height: 18)
            }

            Image(systemName: task.iconName ?? "checkmark.circle")
                .foregroundStyle(Color(hex: task.colorHex) ?? .blue)
            Text(task.title)
                .strikethrough(task.status == .completed)
                .foregroundStyle(task.status == .completed ? .secondary : .primary)
                .lineLimit(1)
            Spacer()
            let progress = store.checklistProgress(for: task.id)
            if progress.totalCount > 0 {
                Text(progress.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            let childCount = row.hasChildren ? store.children(of: task).count : 0
            if childCount > 0 {
                Text("\(childCount)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Image(systemName: task.status.symbolName)
                .font(.caption)
                .foregroundStyle(Color(hex: task.status.colorHex) ?? .secondary)
                .frame(width: 14)
                .help(task.status.displayName)
        }
        .contentShape(Rectangle())
        .scaleEffect(isPulsing ? 1.045 : 1)
        .animation(.spring(response: 0.22, dampingFraction: 0.58), value: isPulsing)
        .onChange(of: store.selectedTaskPulseToken) { _, _ in
            guard store.selectedTaskPulseID == task.id else { return }
            isPulsing = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                isPulsing = false
            }
        }
        .contextMenu {
            TaskContextMenu(store: store, task: task)
        }
        .taskRowSwipeActions(store: store, task: task, labelStyle: .iconOnly)
    }
}

struct SidebarDestinationLabel: View {
    let destination: TimeTrackerStore.DesktopDestination
    let count: Int?

    var body: some View {
        HStack {
            Label(destination.title, systemImage: destination.symbolName)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(.thinMaterial, in: Capsule())
            }
        }
    }
}
