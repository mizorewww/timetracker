#if os(iOS)
import SwiftUI

struct PhoneLargePageHeader: View {
    let destination: TimeTrackerStore.DesktopDestination

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: destination.phoneFilledSymbolName)
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.palette)
                .foregroundStyle(destination.phoneTint, destination.phoneTint.opacity(0.36))
                .frame(width: 38, height: 38)
                .background(destination.phoneTint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))

            Text(destination.title)
                .font(.largeTitle.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.72)

            Spacer(minLength: 0)
        }
        .frame(height: 52)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct PhoneRootListBottomClearanceRow: View {
    var body: some View {
        Color.clear
            .frame(height: PhoneRootChromeMetrics.scrollBottomClearance)
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}
#endif
