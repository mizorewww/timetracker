import SwiftUI

struct TaskDistributionSlice: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let symbolName: String
    let colorHex: String
    let grossSeconds: Int

    var color: Color {
        Color(hex: colorHex) ?? .blue
    }

    var accessibilityTitle: String {
        subtitle.isEmpty ? title : "\(title), \(subtitle)"
    }
}
