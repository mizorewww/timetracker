import SwiftUI

#if os(iOS)
import UIKit
#endif

enum AppLayout {
    static let cardRadius: CGFloat = 8
    /// Corner radius matching the native inset-grouped list card on iOS.
    static let nativeGroupedCardRadius: CGFloat = 26
    static let iconRadius: CGFloat = 7
    static let pageSpacing: CGFloat = 20
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

struct AppCardBackground: ViewModifier {
    var padding: CGFloat = AppLayout.cardPadding
    var stroke: Bool = true

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(
                AppColors.cardBackground,
                in: RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
            )
            .overlay {
                if stroke {
                    RoundedRectangle(cornerRadius: AppLayout.cardRadius, style: .continuous)
                        .stroke(AppColors.border)
                }
            }
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
                .modifier(AppCardBackground(padding: padding, stroke: true))
        }
    }
}

extension View {
    func appCard(padding: CGFloat = AppLayout.cardPadding, stroke: Bool = true) -> some View {
        modifier(AppCardBackground(padding: padding, stroke: stroke))
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
}

struct AppSection<Content: View>: View {
    let title: String
    var subtitle: String?
    var systemImage: String?
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: AppLayout.sectionSpacing) {
            AppSectionHeader(title: title, subtitle: subtitle, systemImage: systemImage)
            content
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
