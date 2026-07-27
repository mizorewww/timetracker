#if os(macOS)
import AppKit
import BlossomColorPickerCore
import SwiftUI

@MainActor
final class MacBlossomColorPresenter {
    private weak var ownerWindow: NSWindow?
    private var window: NSWindow?
    private var model: BlossomColorPickerModel?
    private var localEventMonitor: Any?
    private var appDeactivateObserver: NSObjectProtocol?
    private var ownerCloseObserver: NSObjectProtocol?
    private var dismissTask: Task<Void, Never>?

    func show(
        relativeTo anchorView: NSView,
        model: BlossomColorPickerModel,
        layout: PetalLayout
    ) -> Bool {
        guard let ownerWindow = anchorView.window else {
            return false
        }

        dismissImmediately()
        self.ownerWindow = ownerWindow
        self.model = model

        let anchorRectInWindow = anchorView.convert(anchorView.bounds, to: nil)
        let anchorRectOnScreen = ownerWindow.convertToScreen(anchorRectInWindow)
        let totalSize = ExpandedBlossomView.totalSize(layout: layout)
        let pickerFrame = Self.pickerFrame(
            centeredOn: CGPoint(
                x: anchorRectOnScreen.midX,
                y: anchorRectOnScreen.midY
            ),
            size: totalSize,
            visibleFrame: ownerWindow.screen?.visibleFrame
        )

        let content = ExpandedBlossomView(model: model, layout: layout)
            .frame(width: totalSize, height: totalSize)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("symbol.picker.color.blossom")
        let window = NSWindow(
            contentRect: pickerFrame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false
        window.level = .floating
        window.hasShadow = false
        window.hidesOnDeactivate = true
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.transient, .fullScreenAuxiliary]
        window.contentView = NSHostingView(rootView: content)

        ownerWindow.addChildWindow(window, ordered: .above)
        window.orderFront(nil)
        self.window = window
        installDismissObservers(for: ownerWindow)

        Task { @MainActor in
            model.expand()
        }
        return true
    }

    func dismiss() {
        guard let window, dismissTask == nil else {
            return
        }
        removeDismissObservers()

        dismissTask = Task { @MainActor [weak self, weak window] in
            try? await Task.sleep(for: .milliseconds(350))
            guard Task.isCancelled == false, let self, let window else {
                return
            }
            close(window)
        }
    }

    func dismissImmediately() {
        dismissTask?.cancel()
        dismissTask = nil
        removeDismissObservers()
        guard let window else {
            model = nil
            ownerWindow = nil
            return
        }
        close(window)
    }

    private func close(_ closingWindow: NSWindow) {
        ownerWindow?.removeChildWindow(closingWindow)
        closingWindow.close()
        if window === closingWindow {
            window = nil
            model = nil
            ownerWindow = nil
            dismissTask = nil
        }
    }

    private func installDismissObservers(for ownerWindow: NSWindow) {
        localEventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown]
        ) { [weak self] event in
            guard let self, let window else {
                return event
            }
            if window.frame.contains(NSEvent.mouseLocation) == false {
                model?.collapse()
            }
            return event
        }

        appDeactivateObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.model?.collapse()
            }
        }

        ownerCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: ownerWindow,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.dismissImmediately()
            }
        }
    }

    private func removeDismissObservers() {
        if let localEventMonitor {
            NSEvent.removeMonitor(localEventMonitor)
            self.localEventMonitor = nil
        }
        if let appDeactivateObserver {
            NotificationCenter.default.removeObserver(appDeactivateObserver)
            self.appDeactivateObserver = nil
        }
        if let ownerCloseObserver {
            NotificationCenter.default.removeObserver(ownerCloseObserver)
            self.ownerCloseObserver = nil
        }
    }

    private static func pickerFrame(
        centeredOn center: CGPoint,
        size: CGFloat,
        visibleFrame: CGRect?
    ) -> CGRect {
        var origin = CGPoint(
            x: center.x - size / 2,
            y: center.y - size / 2
        )
        if let visibleFrame {
            let maximumX = max(visibleFrame.minX, visibleFrame.maxX - size)
            let maximumY = max(visibleFrame.minY, visibleFrame.maxY - size)
            origin.x = min(max(origin.x, visibleFrame.minX), maximumX)
            origin.y = min(max(origin.y, visibleFrame.minY), maximumY)
        }
        return CGRect(origin: origin, size: CGSize(width: size, height: size))
    }
}

struct MacBlossomAnchorReader: NSViewRepresentable {
    let onResolve: @MainActor (NSView) -> Void

    func makeNSView(context _: Context) -> AnchorView {
        let view = AnchorView()
        view.onResolve = onResolve
        return view
    }

    func updateNSView(_ nsView: AnchorView, context _: Context) {
        nsView.onResolve = onResolve
        nsView.resolveIfAttached()
    }

    final class AnchorView: NSView {
        var onResolve: (@MainActor (NSView) -> Void)?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            resolveIfAttached()
        }

        func resolveIfAttached() {
            guard window != nil else {
                return
            }
            Task { @MainActor [weak self] in
                guard let self, window != nil else {
                    return
                }
                onResolve?(self)
            }
        }
    }
}
#endif
