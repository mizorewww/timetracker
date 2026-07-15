import Foundation
import SwiftUI

func localized(_ key: String) -> String {
    NSLocalizedString(key, comment: "")
}

enum WidgetDeepLinks {
    static let today = URL(string: "timetracker://open/today")!

    static func startTimer(taskID: UUID) -> URL {
        URL(string: "timetracker://timer/start?taskID=\(taskID.uuidString)")!
    }
}

extension Color {
    init?(hex: String?) {
        guard let hex else { return nil }
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255.0,
            green: Double((value >> 8) & 0xFF) / 255.0,
            blue: Double(value & 0xFF) / 255.0
        )
    }
}
