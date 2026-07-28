#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

final class TimeTrackerAppDelegate: NSObject, NSApplicationDelegate {
    private static var uiTestBootstrapScheduled = false
    private static var uiTestWindow: NSWindow?
    private static var uiTestWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_: Notification) {
        Self.scheduleUITestWindowBootstrap()
    }

    static func scheduleUITestWindowBootstrap() {
        guard CommandLine.arguments.contains("--uitesting"),
              uiTestBootstrapScheduled == false
        else {
            return
        }
        uiTestBootstrapScheduled = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            AppDefaults.shared.set(false, forKey: "NSQuitAlwaysKeepsWindows")
            NSApp.setActivationPolicy(.regular)
            NSApp.activate()
            _ = NSRunningApplication.current.activate(
                options: [.activateAllWindows]
            )
            Self.installUITestWindowObserver()
            let visibleContentWindow = NSApp.windows.first { window in
                window.isVisible && window.canBecomeMain && !window.title.isEmpty
            }

            if let visibleContentWindow {
                Self.positionUITestWindow(visibleContentWindow)
                visibleContentWindow.makeKeyAndOrderFront(nil)
                visibleContentWindow.orderFrontRegardless()
            } else {
                NSApp.sendAction(Selector(("newWindow:")), to: nil, from: nil)
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                Self.openUITestWindowIfNeeded()
                Self.resizeUITestWindowIfRequested()
            }
        }
    }

    private static func openUITestWindowIfNeeded() {
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
        NSApp.activate()
        _ = NSRunningApplication.current.activate(
            options: [.activateAllWindows]
        )
        Self.uiTestWindow = window
    }

    private static func installUITestWindowObserver() {
        guard uiTestWindowObserver == nil else { return }
        uiTestWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            positionUITestWindow(window)
        }
    }

    private static func positionUITestWindow(_ window: NSWindow) {
        guard window.canBecomeMain, !window.title.isEmpty,
              let screen = NSScreen.screens.first
        else {
            return
        }
        window.collectionBehavior.insert(.moveToActiveSpace)
        let visibleFrame = screen.visibleFrame
        let origin = NSPoint(
            x: visibleFrame.midX - (window.frame.width / 2),
            y: visibleFrame.midY - (window.frame.height / 2)
        )
        window.setFrameOrigin(origin)
    }

    private static func resizeUITestWindowIfRequested() {
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
