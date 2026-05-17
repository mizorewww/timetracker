#if os(iOS)
import SwiftUI

struct PhoneBottomDestinationButton: View {
    let destination: TimeTrackerStore.DesktopDestination
    let isSelected: Bool
    let select: () -> Void

    var body: some View {
        Button(action: select) {
            ZStack {
                if isSelected {
                    Capsule()
                        .fill(destination.phoneTint.opacity(0.18))
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .padding(.horizontal, 7)
                        .overlay {
                            Capsule()
                                .stroke(destination.phoneTint.opacity(0.18), lineWidth: 0.5)
                                .padding(.horizontal, 7)
                        }
                        .allowsHitTesting(false)
                        .zIndex(0)
                }

                VStack(spacing: 3) {
                    Image(systemName: isSelected ? destination.phoneFilledSymbolName : destination.phoneSymbolName)
                        .font(.system(size: 19, weight: .semibold))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(
                            isSelected ? destination.phoneTint : destination.phoneTint.opacity(0.82),
                            destination.phoneTint.opacity(isSelected ? 0.46 : 0.28)
                        )
                        .frame(height: 22)

                    Text(destination.title)
                        .font(.caption2.weight(isSelected ? .semibold : .medium))
                        .lineLimit(1)
                        .minimumScaleFactor(0.72)
                        .foregroundStyle(isSelected ? destination.phoneTint : Color.secondary)
                }
                .zIndex(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: PhoneRootChromeMetrics.bottomBarItemHeight)
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(destination.title)
    }
}
#endif
