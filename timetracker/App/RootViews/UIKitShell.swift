#if os(iOS)
import SwiftUI
import UIKit

/// The iOS/iPadOS app shell, in UIKit (AD-144). Pages not yet rewritten are
/// hosted SwiftUI views given the scene objects they would have inherited.
struct UIKitShellView: UIViewControllerRepresentable {
    let store: TimeTrackerStore
    @Environment(AppPresentationRouter.self) private var presentationRouter
    @Environment(AppSceneFeedbackRouter.self) private var feedbackRouter

    func makeUIViewController(context _: Context) -> ShellController {
        ShellController(scene: ShellScene(
            store: store,
            presentationRouter: presentationRouter,
            feedbackRouter: feedbackRouter
        ))
    }

    func updateUIViewController(_: ShellController, context _: Context) {}
}

/// What every page of the shell needs from the scene.
struct ShellScene {
    let store: TimeTrackerStore
    let presentationRouter: AppPresentationRouter
    let feedbackRouter: AppSceneFeedbackRouter

    func host(_ page: some View, shell: RootLayoutPolicy.Shell) -> UIViewController {
        UIHostingController(rootView: page
            .environment(presentationRouter)
            .environment(feedbackRouter)
            .environment(\.layoutShell, shell))
    }
}

/// Shows the tab shell or the split shell for the current width (AD-139).
final class ShellController: UIViewController {
    private let scene: ShellScene
    private var shell: RootLayoutPolicy.Shell?

    init(scene: ShellScene) {
        self.scene = scene
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let next = RootLayoutPolicy.shell(
            measured: RootLayoutPolicy.shell(forWidth: view.bounds.width),
            horizontalSizeClass: UserInterfaceSizeClass(traitCollection.horizontalSizeClass)
        )
        guard next != shell else { return }
        shell = next
        show(next == .compact ? TabShellController(scene: scene) : SplitShellController(scene: scene))
    }

    private func show(_ content: UIViewController) {
        for child in children {
            child.willMove(toParent: nil)
            child.view.removeFromSuperview()
            child.removeFromParent()
        }
        addChild(content)
        content.view.frame = view.bounds
        content.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(content.view)
        content.didMove(toParent: self)
    }
}

/// One tab per destination; the selected tab follows `desktopDestination`.
final class TabShellController: UITabBarController, UITabBarControllerDelegate {
    private let scene: ShellScene

    init(scene: ShellScene) {
        self.scene = scene
        super.init(nibName: nil, bundle: nil)
        delegate = self
        tabBarMinimizeBehavior = .onScrollDown
        tabs = TimeTrackerStore.DesktopDestination.allCases.map { destination in
            UITab(
                title: destination.title,
                image: UIImage(systemName: destination.visual.symbolName),
                identifier: destination.rawValue
            ) { _ in
                scene.host(
                    CompactTabPage(
                        store: scene.store,
                        destination: destination,
                        openSettings: { scene.presentationRouter.present(.settings) }
                    ),
                    shell: .compact
                )
            }
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func updateProperties() {
        super.updateProperties()
        selectedTab = tab(forIdentifier: scene.store.desktopDestination.rawValue)
    }

    func tabBarController(_: UITabBarController, didSelectTab tab: UITab, previousTab _: UITab?) {
        guard let destination = TimeTrackerStore.DesktopDestination(rawValue: tab.identifier) else { return }
        scene.store.desktopDestination = destination
    }
}

/// Sidebar plus detail for widths that hold both columns.
final class SplitShellController: UISplitViewController {
    init(scene: ShellScene) {
        super.init(style: .doubleColumn)
        preferredDisplayMode = .oneBesideSecondary
        preferredSplitBehavior = .tile
        minimumPrimaryColumnWidth = 220
        maximumPrimaryColumnWidth = 300
        setViewController(scene.host(SidebarView(store: scene.store), shell: .regular), for: .primary)
        setViewController(scene.host(DesktopContentView(store: scene.store), shell: .regular), for: .secondary)
        // The detail page brings its own navigation stack.
        viewController(for: .secondary)?.navigationController?.isNavigationBarHidden = true
        // Kept verbatim: this is the identifier the existing XCUITests select on.
        view.accessibilityIdentifier = "ipad.splitNavigation"
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) is not supported")
    }
}
#endif
