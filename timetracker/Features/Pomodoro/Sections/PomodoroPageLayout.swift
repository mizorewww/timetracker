import SwiftUI

struct PomodoroPageLayout<Primary: View, Secondary: View>: View {
    private let primary: Primary
    private let secondary: Secondary

    init(
        @ViewBuilder primary: () -> Primary,
        @ViewBuilder secondary: () -> Secondary
    ) {
        self.primary = primary()
        self.secondary = secondary()
    }

    var body: some View {
        ScrollView {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .top, spacing: 24) {
                    primary
                        .frame(minWidth: 440, maxWidth: 580)
                    secondary
                        .frame(minWidth: 280, maxWidth: 360)
                }

                VStack(spacing: 20) {
                    primary
                    secondary
                }
                .frame(maxWidth: 600)
            }
            .frame(maxWidth: AppLayout.desktopReadableWidth)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, AppLayout.compactPagePadding)
            .padding(.vertical, 24)
        }
        .accessibilityIdentifier("pomodoro.dashboard")
    }
}
