#if os(macOS)
import SwiftData
import SwiftUI

struct SettingsSceneView: View {
    @Environment(\.modelContext) private var modelContext
    @StateObject private var store = TimeTrackerStore()

    var body: some View {
        SettingsView(store: store)
            .task {
                store.configureIfNeeded(context: modelContext)
            }
    }
}
#endif
