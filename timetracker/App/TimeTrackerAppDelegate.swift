#if os(macOS)
import AppKit
import SwiftData
import SwiftUI

@MainActor
final class TimeTrackerAppDelegate: NSObject, NSApplicationDelegate {
    #if DEBUG
    private static var uiTestBootstrapScheduled = false
    private static var uiTestWindow: NSWindow?
    private static var uiTestWindowObserver: NSObjectProtocol?
    #endif

    func applicationDidFinishLaunching(_: Notification) {
        Self.scheduleUITestWindowBootstrap()
    }

    static func scheduleUITestWindowBootstrap() {
        #if DEBUG
        guard CommandLine.arguments.contains(AppRuntimeEnvironment.uiTestingArgument),
              uiTestBootstrapScheduled == false
        else {
            return
        }
        uiTestBootstrapScheduled = true

        AppDefaults.shared.set(false, forKey: "NSQuitAlwaysKeepsWindows")
        installUITestWindowObserver()
        DispatchQueue.main.async {
            prepareUITestWindow()
        }
        #endif
    }

    #if DEBUG
    private static func prepareUITestWindow() {
        let existingWindow = NSApp.windows.first { window in
            window.isVisible && window.canBecomeMain && !window.title.isEmpty
        }
        let window = existingWindow ?? makeUITestWindow()
        resizeUITestWindowIfRequested(window)
        positionUITestWindow(window)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        _ = NSRunningApplication.current.activate(options: [.activateAllWindows])
    }

    private static func makeUITestWindow() -> NSWindow {
        let rootView = ContentView(store: timetrackerApp.applicationStore)
            .frame(minWidth: 680, minHeight: 500)
            .modelContainer(timetrackerApp.applicationModelContainer)
            .environment(MacKeyboardShortcutSettings())
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
        uiTestWindow = window
        return window
    }

    private static func installUITestWindowObserver() {
        guard uiTestWindowObserver == nil else { return }
        uiTestWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            resizeUITestWindowIfRequested(window)
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

    private static func resizeUITestWindowIfRequested(_ window: NSWindow) {
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
        window.setContentSize(NSSize(width: width, height: height))
    }
    #endif
}
#endif
