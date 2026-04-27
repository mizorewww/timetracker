import SwiftUI

enum AppLayout {
    static let cardRadius: CGFloat = 8
    static let iconRadius: CGFloat = 7
    static let pageSpacing: CGFloat = 20
    static let sectionSpacing: CGFloat = 12
    static let cardPadding: CGFloat = 16
    static let compactPagePadding: CGFloat = 18
    static let regularPagePadding: CGFloat = 28
    static let desktopReadableWidth: CGFloat = 980
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

extension View {
    func appCard(padding: CGFloat = AppLayout.cardPadding, stroke: Bool = true) -> some View {
        modifier(AppCardBackground(padding: padding, stroke: stroke))
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
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            content
        }
    }
}

struct AppRowIcon: View {
    let systemImage: String
    var tint: Color = .blue

    var body: some View {
        Image(systemName: systemImage)
            .font(.body.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 30, height: 30)
            .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: AppLayout.iconRadius, style: .continuous))
    }
}
