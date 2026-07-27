import SwiftUI

struct InformationPresentationButton<Destination: View>: View {
    let title: String
    let accessibilityIdentifier: String
    private let destination: Destination

    @State private var isPresented = false

    init(
        title: String,
        accessibilityIdentifier: String,
        @ViewBuilder destination: () -> Destination
    ) {
        self.title = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.destination = destination()
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "info.circle")
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .frame(
            minWidth: AppLayout.minimumInteractiveTarget,
            minHeight: AppLayout.minimumInteractiveTarget
        )
        .contentShape(Rectangle())
        .accessibilityLabel(title)
        .accessibilityIdentifier(accessibilityIdentifier)
        .help(title)
        .popover(isPresented: $isPresented) {
            destination
                .presentationCompactAdaptation(.sheet)
        }
    }
}

struct InformationGuideRow: View {
    let icon: String
    let title: String
    let bodyText: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.blue)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(titleFont)
                Text(bodyText)
                    .font(bodyFont)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
    }

    private var titleFont: Font {
        #if os(macOS)
        .body.weight(.semibold)
        #else
        .subheadline.weight(.semibold)
        #endif
    }

    private var bodyFont: Font {
        #if os(macOS)
        .body
        #else
        .caption
        #endif
    }
}
