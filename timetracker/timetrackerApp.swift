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
            DailySummary.self,
            CountdownEvent.self
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
        let emergencyConfiguration = ModelConfiguration(
            "TimeTrackerEmergency",
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        guard AppCloudSync.isEnabled else {
            AppCloudSync.recordCloudKitDisabledByUser()
            do {
                return try ModelContainer(
                    for: schema,
                    migrationPlan: TimeTrackerMigrationPlan.self,
                    configurations: [localConfiguration]
                )
            } catch {
                return makeEmergencyModelContainer(
                    schema: schema,
                    configuration: emergencyConfiguration,
                    error: error
                )
            }
        }

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
                return makeEmergencyModelContainer(
                    schema: schema,
                    configuration: emergencyConfiguration,
                    error: error
                )
            }
        }
    }

    private static func makeEmergencyModelContainer(
        schema: Schema,
        configuration: ModelConfiguration,
        error: Error
    ) -> ModelContainer {
        AppCloudSync.recordEmergencyInMemoryFallback(error: error)
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: TimeTrackerMigrationPlan.self,
                configurations: [configuration]
            )
        } catch {
            preconditionFailure("Could not create emergency in-memory ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        #if os(macOS)
        WindowGroup {
            ContentView()
                .frame(minWidth: 960, minHeight: 680)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            TimeTrackerCommands()
        }

        Settings {
            SettingsSceneView()
                .modelContainer(sharedModelContainer)
                .frame(width: 640, height: 620)
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}

#if os(macOS)
struct SettingsSceneView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store = TimeTrackerStore()

    var body: some View {
        SettingsView(store: store)
            .task {
                store.configureIfNeeded(context: modelContext)
            }
    }
}

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
                .frame(minWidth: 960, minHeight: 680)
                .modelContainer(container)
            let hostingController = NSHostingController(rootView: rootView)
            let window = NSWindow(
                contentRect: NSRect(x: 220, y: 160, width: 1180, height: 760),
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
            Button(AppStrings.newTask) {
                newTask?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(newTask == nil)

            Button(AppStrings.addTime) {
                manualTime?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(manualTime == nil)
        }

        CommandMenu(AppStrings.appName) {
            Button(AppStrings.newTask) {
                newTask?()
            }
            .keyboardShortcut("n", modifiers: [.command])
            .disabled(newTask == nil)

            Button(AppStrings.addTime) {
                manualTime?()
            }
            .keyboardShortcut("m", modifiers: [.command, .shift])
            .disabled(manualTime == nil)

            Divider()

            Button(AppStrings.localized("menu.startSelectedTask")) {
                startTimer?()
            }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(startTimer == nil)

            Button(AppStrings.localized("menu.startPomodoro")) {
                startPomodoro?()
            }
            .keyboardShortcut("p", modifiers: [.command, .shift])
            .disabled(startPomodoro == nil)

            Divider()

            Button(AppStrings.localized("menu.refreshData")) {
                refresh?()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(refresh == nil)
        }
    }
}
#endif
