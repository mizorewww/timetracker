//
//  timetrackerApp.swift
//  timetracker
//
//  Created by gaozexuan on 2026/4/25.
//

import SwiftData
import SwiftUI

@main
struct timetrackerApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(TimeTrackerAppDelegate.self) private var appDelegate
    #endif

    var sharedModelContainer: ModelContainer = timetrackerApp.makeModelContainer()

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
