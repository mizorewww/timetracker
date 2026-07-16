#if os(macOS)
import SwiftData
import SwiftUI

struct SettingsSceneView: View {
    @Environment(\.modelContext) private var modelContext
    let store: TimeTrackerStore
    @State private var presentationRouter = AppPresentationRouter()

    var body: some View {
        SettingsView(store: store)
            .environment(presentationRouter)
            .appPresentationHost(store: store, router: presentationRouter)
            .task {
                store.configureIfNeeded(context: modelContext)
            }
    }
}
#endif
