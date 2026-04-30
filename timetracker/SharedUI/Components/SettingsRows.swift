import SwiftUI

struct SettingsActionLabel: View {
    let title: String
    let systemImage: String

    var body: some View {
        Label {
            Text(title)
                .font(.body)
        } icon: {
            Image(systemName: systemImage)
        }
    }
}
