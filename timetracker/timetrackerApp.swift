//
//  timetrackerApp.swift
//  timetracker
//
//  Created by gaozexuan on 2026/4/25.
//

import SwiftUI
import SwiftData
#if os(macOS)
import AppKit
#endif

@main
struct timetrackerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(TimeTrackerAppDelegate.self) private var appDelegate
    #endif

    var sharedModelContainer: ModelContainer = timetrackerApp.makeModelContainer()

    static func makeUITestModelContainer() throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "TimeTrackerUITests",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        AppCloudSync.recordUITesting()
        return try ModelContainer(
            for: schema,
            migrationPlan: TimeTrackerMigrationPlan.self,
            configurations: [configuration]
        )
    }

    private static var schema: Schema {
        Schema([
            TaskNode.self,
            TimeSession.self,
            TimeSegment.self,
            PomodoroRun.self,
            DailySummary.self
        ])
    }

    private static func makeModelContainer() -> ModelContainer {
        let schema = Self.schema
        if CommandLine.arguments.contains("--uitesting") {
            do {
                return try makeUITestModelContainer()
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
    }

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
final class TimeTrackerAppDelegate: NSObject, NSApplicationDelegate {
    private var uiTestWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.contains("--uitesting") else { return }

        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        NSApp.setActivationPolicy(.regular)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApp.activate(ignoringOtherApps: true)
            let hasVisibleContentWindow = NSApp.windows.contains { window in
                window.isVisible && window.canBecomeMain && !window.title.isEmpty
            }

            if !hasVisibleContentWindow {
                NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                self.openUITestWindowIfNeeded()
            }
        }
    }

    private func openUITestWindowIfNeeded() {
        guard CommandLine.arguments.contains("--uitesting") else { return }

        let hasVisibleContentWindow = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeMain && !window.title.isEmpty
        }
        guard !hasVisibleContentWindow else { return }

        do {
            let container = try timetrackerApp.makeUITestModelContainer()
            let rootView = ContentView()
                .frame(minWidth: 1120, minHeight: 700)
                .modelContainer(container)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 220, y: 160, width: 1240, height: 760),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Time Tracker"
            window.contentViewController = hostingController
            window.setFrameAutosaveName("TimeTrackerUITestWindow")
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            uiTestWindow = window
        } catch {
            assertionFailure("Could not create UI test fallback window: \(error)")
        }
    }
}

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
