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
    @State private var store = TimeTrackerStore()
    #endif

    static let applicationModelContainer = timetrackerApp.makeModelContainer()
    var sharedModelContainer: ModelContainer = Self.applicationModelContainer

    init() {
        #if os(iOS) && canImport(WatchConnectivity)
        // WCSession must be activated during application startup so background
        // transfers are not dependent on a SwiftUI view having appeared.
        WatchConnectivityBridge.shared.activateIfSupported()
        #endif
    }

    var body: some Scene {
        #if os(macOS)
        Window(AppStrings.localized("app.name"), id: "main") {
            ContentView(store: store)
                .frame(minWidth: 680, minHeight: 500)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            TimeTrackerCommands()
        }

        Settings {
            SettingsSceneView(store: store)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 640, idealWidth: 720, minHeight: 620, idealHeight: 720)
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
