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
        if CommandLine.arguments.contains("--uitesting") {
            let configuration = ModelConfiguration(
                "TimeTrackerUITests",
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            do {
                AppCloudSync.recordUITesting()
                return try ModelContainer(
                    for: schema,
                    migrationPlan: TimeTrackerMigrationPlan.self,
                    configurations: [configuration]
                )
            } catch {
                fatalError("Could not create UI test ModelContainer: \(error)")
            }
        }

        let cloudConfiguration = ModelConfiguration(
            "TimeTracker",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .private(AppCloudSync.containerIdentifier)
        )
        let localConfiguration = ModelConfiguration(
            "TimeTracker",
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none
        )

        do {
            let container = try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [cloudConfiguration]
            )
            AppCloudSync.recordCloudKitEnabled()
            return container
        } catch {
            AppCloudSync.recordLocalFallback(error: error)
            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: TimeTrackerMigrationPlan.self,
                    configurations: [localConfiguration]
                )
            } catch {
                fatalError("Could not create local ModelContainer: \(error)")
            }
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
