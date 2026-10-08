import SwiftUI

struct SettingsTextFieldRow: View {
    let title: String
    @Binding var text: String
    let systemImage: String
    var tint: Color = .accentColor
    var isSecure = false
    var fieldAlignment: Alignment = .trailing
    var textAlignment: TextAlignment = .leading
    var usesSentenceCapitalization = false
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
                    inputField
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                LabeledContent {
                    inputField
                        .frame(maxWidth: .infinity, alignment: fieldAlignment)
                } label: {
                    SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
                }
            }
        }
        .settingsRowSeparatorAligned()
    }

    @ViewBuilder
    private var inputField: some View {
        Group {
            if isSecure {
                SecureField(title, text: $text)
            } else {
                TextField(title, text: $text)
            }
        }
        .labelsHidden()
        .accessibilityLabel(title)
        #if os(iOS)
        .textInputAutocapitalization(usesSentenceCapitalization ? .sentences : .never)
        #endif
        .autocorrectionDisabled(!usesSentenceCapitalization)
        .multilineTextAlignment(textAlignment)
    }
}
