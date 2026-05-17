#if os(macOS)
import SwiftData
import SwiftUI

struct SettingsSceneView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store = TimeTrackerStore()

    var body: some View {
        SettingsView(store: store)
            .preferredColorScheme(settingsColorScheme)
            .task {
                store.configureIfNeeded(context: modelContext)
            }
    }

    private var settingsColorScheme: ColorScheme? {
        switch store.preferences.preferredColorScheme {
        case "light": return .light
        case "dark": return .dark
        default: return nil
        }
    }
}
#endif
