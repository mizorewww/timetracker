import SwiftUI

#if os(iOS)
import UIKit
#endif

enum AppLayout {
    #if os(macOS)
    static let cardRadius: CGFloat = 18
    #else
    static let cardRadius: CGFloat = 22
    #endif
    /// Corner radius matching the native inset-grouped list card on iOS.
    static let nativeGroupedCardRadius: CGFloat = 26
    static let iconRadius: CGFloat = 7
    static let sectionSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let compactPagePadding: CGFloat = 18
    static let regularPagePadding: CGFloat = 28
    static let desktopReadableWidth: CGFloat = 980
    #if os(iOS)
    static let minimumInteractiveTarget: CGFloat = 44
    #else
    static let minimumInteractiveTarget: CGFloat = 28
    #endif
}

enum AppMotion {
    static let stateChange = Animation.snappy(duration: 0.22)
    static let structuralChange = Animation.snappy(duration: 0.28)
    static let opacity = Animation.easeOut(duration: 0.16)
    static let press = Animation.easeOut(duration: 0.12)
}

/// A design-language card: `cardBackground` fill with the card shadow, plus
/// a faint light edge in dark mode so cards separate from the window.
private struct AppCardSurface: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
        if colorScheme == .dark {
            shape
                .fill(AppColors.cardBackground)
                .strokeBorder(.white.opacity(0.06))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        } else {
            shape
                .fill(AppColors.cardBackground)
                .shadow(color: AppColors.shadowInk.opacity(0.04), radius: 1, y: 1)
                .shadow(color: AppColors.shadowInk.opacity(0.06), radius: 10, y: 6)
        }
    }
}

private struct AppCardBackground: ViewModifier {
    let padding: CGFloat

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(AppCardSurface())
    }
}

private struct AppNativeCardBackground: ViewModifier {
    let padding: CGFloat
    @Environment(\.layoutShell) private var layoutShell

    func body(content: Content) -> some View {
        switch layoutShell {
        case .compact:
            content
                .padding(padding)
                .background(
                    AppColors.cardBackground,
                    in: RoundedRectangle(
                        cornerRadius: AppLayout.nativeGroupedCardRadius,
                        style: .continuous
                    )
                )
        case .regular:
            content
                .modifier(AppCardBackground(padding: padding))
        }
    }
}

extension View {
    func appCard(padding: CGFloat = AppLayout.cardPadding) -> some View {
        modifier(AppCardBackground(padding: padding))
    }

    /// Card matching the surrounding surface's native card language.
    ///
    /// The compact shell lays content out as an inset-grouped list, so cards
    /// there take the grouped look (large continuous corners, grouped
    /// background, no stroke). The regular shell draws a card canvas, so cards
    /// there take the ordinary app card. Keyed off the shell rather than the
    /// device, so an iPad in Split View and a narrow Mac window match iPhone.
    func appNativeCard(padding: CGFloat = AppLayout.cardPadding) -> some View {
        modifier(AppNativeCardBackground(padding: padding))
    }

    @ViewBuilder
    func platformSheetFrame(width: CGFloat, height: CGFloat) -> some View {
        #if os(macOS)
        frame(minWidth: width, idealWidth: width, minHeight: height, idealHeight: height)
        #else
        self
        #endif
    }

    /// Native list style for a sheet/pushed surface: inset-grouped on iOS,
    /// plain inset elsewhere.
    @ViewBuilder
    func appSheetListStyle() -> some View {
        #if os(iOS)
        listStyle(.insetGrouped)
        #else
        listStyle(.inset)
        #endif
    }

    /// Inline navigation title on platforms that support it; no-op on macOS.
    @ViewBuilder
    func appInlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// Runs `action` on every system clock, calendar-day and time-zone change.
    func onSystemClockChange(_ action: @escaping () -> Void) -> some View {
        onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            action()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemClockDidChange)) { _ in
            action()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSSystemTimeZoneDidChange)) { _ in
            action()
        }
    }
}

struct AppRowIcon: View {
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 17, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppLayout.iconRadius, style: .continuous))
            .accessibilityHidden(true)
    }
}

extension View {
    /// Bottom scroll margin that keeps the last rows clear of the tab bar and
    /// bottom accessories, which grow at accessibility text sizes.
    func bottomScrollClearance(accessibilitySize: CGFloat = 112) -> some View {
        modifier(BottomScrollClearance(accessibilityMargin: accessibilitySize))
    }
}

private struct BottomScrollClearance: ViewModifier {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let accessibilityMargin: CGFloat

    func body(content: Content) -> some View {
        content.contentMargins(
            .bottom,
            dynamicTypeSize.isAccessibilitySize ? accessibilityMargin : 16,
            for: .scrollContent
        )
    }
}
