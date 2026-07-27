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
    static let applicationStore = TimeTrackerStore()
    @NSApplicationDelegateAdaptor(TimeTrackerAppDelegate.self) private var appDelegate
    @State private var store = timetrackerApp.applicationStore
    @State private var shortcutSettings = MacKeyboardShortcutSettings()
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
                .environment(shortcutSettings)
        }
        .modelContainer(sharedModelContainer)
        .defaultSize(width: 1180, height: 760)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            SidebarCommands()
            TimeTrackerCommands(shortcutSettings: shortcutSettings)
        }

        Settings {
            SettingsSceneView(store: store)
                .modelContainer(sharedModelContainer)
                .frame(minWidth: 640, idealWidth: 720, minHeight: 620, idealHeight: 720)
                .environment(shortcutSettings)
        }
        #else
        WindowGroup {
            ContentView()
        }
        .modelContainer(sharedModelContainer)
        #endif
    }
}
