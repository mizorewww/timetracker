import SwiftUI

struct PomodoroPageLayout<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = PomodoroPageLayoutPolicy(
                viewportWidth: proxy.size.width,
                prefersSingleColumn: dynamicTypeSize.isAccessibilitySize
            )

            ScrollView {
                Group {
                    if layout.usesTwoColumnContent {
                        HStack(alignment: .top, spacing: layout.columnSpacing) {
                            primary
                                .frame(maxWidth: layout.primaryColumnMaxWidth)
                            secondary
                                .frame(width: layout.supportingColumnWidth)
                        }
                    } else {
                        VStack(spacing: layout.singleColumnSpacing) {
                            primary
                            secondary
                        }
                        .frame(maxWidth: layout.singleColumnMaxWidth)
                    }
                }
                .frame(width: layout.contentWidth)
                .padding(.vertical, 24)
                .frame(maxWidth: .infinity)
            }
        }
        .accessibilityIdentifier("pomodoro.dashboard")
    }
}

struct PomodoroPageLayoutPolicy {
    static let twoColumnMinimumWidth: CGFloat = 744

    let viewportWidth: CGFloat
    let prefersSingleColumn: Bool

    let columnSpacing: CGFloat = 24
    let singleColumnSpacing: CGFloat = 20
    let primaryColumnMaxWidth: CGFloat = 580
    let singleColumnMaxWidth: CGFloat = 600

    var contentWidth: CGFloat {
        min(
            max(0, viewportWidth - (AppLayout.compactPagePadding * 2)),
            AppLayout.desktopReadableWidth
        )
    }

    var usesTwoColumnContent: Bool {
        !prefersSingleColumn && contentWidth >= Self.twoColumnMinimumWidth
    }

    var supportingColumnWidth: CGFloat {
        min(340, max(280, contentWidth * 0.34))
    }
}
