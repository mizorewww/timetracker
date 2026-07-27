#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

final class TimeTrackerAppDelegate: NSObject, NSApplicationDelegate {
    private var uiTestWindow: NSWindow?

    func applicationDidFinishLaunching(_: Notification) {
        guard CommandLine.arguments.contains("--uitesting") else { return }

        AppDefaults.shared.set(false, forKey: "NSQuitAlwaysKeepsWindows")
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
                self.resizeUITestWindowIfRequested()
            }
        }
    }

    private func openUITestWindowIfNeeded() {
        guard CommandLine.arguments.contains("--uitesting") else { return }

        let hasVisibleContentWindow = NSApp.windows.contains { window in
            window.isVisible && window.canBecomeMain && !window.title.isEmpty
        }
        guard !hasVisibleContentWindow else { return }

        let rootView = ContentView(store: timetrackerApp.applicationStore)
            .frame(minWidth: 680, minHeight: 500)
            .modelContainer(timetrackerApp.applicationModelContainer)
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
    }

    private func resizeUITestWindowIfRequested() {
        let environment = ProcessInfo.processInfo.environment
        guard
            let widthText = environment["TIMETRACKER_UI_TEST_WINDOW_WIDTH"],
            let width = Double(widthText),
            width.isFinite,
            width > 0
        else {
            return
        }
        let height = environment["TIMETRACKER_UI_TEST_WINDOW_HEIGHT"]
            .flatMap(Double.init)
            .flatMap { value in
                value.isFinite && value > 0 ? value : nil
            } ?? 900
        guard let window = NSApp.windows.first(where: { window in
            window.isVisible && window.canBecomeMain && !window.title.isEmpty
        }) else {
            return
        }
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
}
#endif
