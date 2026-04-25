//
//  timetrackerApp.swift
//  timetracker
//
//  Created by gaozexuan on 2026/4/25.
//

import SwiftUI
import SwiftData

@main
struct timetrackerApp: App {
    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [modelConfiguration]
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                #if os(macOS)
                .frame(minWidth: 1120, minHeight: 700)
                #endif
        }
        .modelContainer(sharedModelContainer)
        #if os(macOS)
        .defaultSize(width: 1240, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            TimeTrackerCommands()
        }
        #endif
    }
}

#if os(macOS)
struct TimeTrackerCommands: Commands {
    @FocusedValue(\.newTaskAction) private var newTask
    @FocusedValue(\.manualTimeAction) private var manualTime
    @FocusedValue(\.startTimerAction) private var startTimer
    @FocusedValue(\.startPomodoroAction) private var startPomodoro
    @FocusedValue(\.refreshAction) private var refresh

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Task") {
                newTask?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(newTask == nil)

            Button("Add Manual Time") {
                manualTime?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(manualTime == nil)
        }

        CommandMenu("Time Tracker") {
            Button("New Task") {
                newTask?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(newTask == nil)

            Button("Add Manual Time") {
                manualTime?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(manualTime == nil)

            Divider()

            Button("Start Selected Timer") {
                startTimer?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(startTimer == nil)

            Button("Start Pomodoro") {
                startPomodoro?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(startPomodoro == nil)

            Divider()

            Button("Refresh Ledger") {
                refresh?()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(refresh == nil)
        }
    }
}
#endif
