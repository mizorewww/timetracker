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

struct SettingsNumberFieldRow: View {
    let title: String
    let value: Binding<Int>
    let formatter: NumberFormatter
    let systemImage: String
    var tint: Color = .accentColor
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
                    numberField
                        .textFieldStyle(.roundedBorder)
                }
            } else {
                LabeledContent {
                    numberField
                } label: {
                    SettingsRowLabel(title: title, systemImage: systemImage, tint: tint)
                }
            }
        }
        .settingsRowSeparatorAligned()
    }

    private var numberField: some View {
        TextField(title, value: value, formatter: formatter)
            .labelsHidden()
            .accessibilityLabel(title)
            .multilineTextAlignment(dynamicTypeSize.isAccessibilitySize ? .leading : .trailing)
    }
}
