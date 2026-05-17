#if os(iOS)
import SwiftUI

private struct PhoneRootChromeModifier: ViewModifier {
    @EnvironmentObject private var chrome: PhoneChromeCoordinator
    @Namespace private var titleGlassNamespace
    let destination: TimeTrackerStore.DesktopDestination

    func body(content: Content) -> some View {
        let opacity = chrome.toolbarTitleOpacity(for: destination)
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .overlay(alignment: .top) {
                PhoneFloatingToolbarTitle(
                    destination: destination,
                    opacity: opacity,
                    namespace: titleGlassNamespace
                )
            }
    }
}

private struct PhoneFloatingToolbarTitle: View {
    let destination: TimeTrackerStore.DesktopDestination
    let opacity: Double
    let namespace: Namespace.ID

    var body: some View {
        GlassEffectContainer(spacing: 8) {
            Text(destination.title)
                .font(.headline.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 18)
                .frame(minWidth: 94)
                .frame(height: 36)
                .glassEffect(.regular, in: Capsule())
                .glassEffectID("phone-floating-title", in: namespace)
                .glassEffectTransition(.materialize)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
        .opacity(opacity)
        .scaleEffect(0.96 + (0.04 * CGFloat(opacity)))
        .animation(.smooth(duration: 0.18), value: opacity)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

private struct PhoneChromeScrollObserver: ViewModifier {
    @EnvironmentObject private var chrome: PhoneChromeCoordinator
    let destination: TimeTrackerStore.DesktopDestination

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: PhoneChromeScrollState.self) { geometry in
                PhoneChromeScrollState(
                    offsetY: max(0, geometry.contentOffset.y + geometry.contentInsets.top),
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height
                )
            } action: { _, state in
                chrome.updateScroll(state, for: destination)
            }
    }
}

private struct PhoneRootScrollBehaviorModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
    }
}

private struct PhoneSecondaryDestinationModifier: ViewModifier {
    @EnvironmentObject private var chrome: PhoneChromeCoordinator
    let destination: TimeTrackerStore.DesktopDestination
    @State private var isRegistered = false

    func body(content: Content) -> some View {
        content
            .onAppear {
                guard !isRegistered else { return }
                isRegistered = true
                chrome.enterSecondary(for: destination)
            }
            .onDisappear {
                guard isRegistered else { return }
                isRegistered = false
                chrome.exitSecondary(for: destination)
            }
    }
}

extension View {
    @ViewBuilder
    func phoneRootChrome(destination: TimeTrackerStore.DesktopDestination, enabled: Bool = true) -> some View {
        if enabled {
            modifier(PhoneRootChromeModifier(destination: destination))
        } else {
            self
        }
    }

    @ViewBuilder
    func phoneChromeScrollObserver(destination: TimeTrackerStore.DesktopDestination, enabled: Bool = true) -> some View {
        if enabled {
            modifier(PhoneChromeScrollObserver(destination: destination))
        } else {
            self
        }
    }

    @ViewBuilder
    func phoneSecondaryDestination(_ destination: TimeTrackerStore.DesktopDestination) -> some View {
        modifier(PhoneSecondaryDestinationModifier(destination: destination))
    }

    @ViewBuilder
    func phoneRootScrollMargins(enabled: Bool = true) -> some View {
        if enabled {
            contentMargins(.top, 0, for: .scrollContent)
                .modifier(PhoneRootScrollBehaviorModifier())
        } else {
            self
        }
    }

    @ViewBuilder
    func phoneRootScrollBehavior(enabled: Bool = true) -> some View {
        if enabled {
            modifier(PhoneRootScrollBehaviorModifier())
        } else {
            self
        }
    }
}
#endif
