#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

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
#endif
