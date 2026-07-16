#if os(macOS)
import SwiftData
import SwiftUI

struct SettingsSceneView: View {
    @Environment(\.modelContext) private var modelContext
    let store: TimeTrackerStore
    @State private var presentationRouter = AppPresentationRouter()
    @State private var feedbackRouter = AppSceneFeedbackRouter()

    var body: some View {
        SettingsView(store: store)
            .environment(presentationRouter)
            .environment(feedbackRouter)
            .appPresentationHost(store: store, router: presentationRouter)
            .appSceneFeedbackHost(router: feedbackRouter)
            .task {
                store.configureIfNeeded(context: modelContext)
            }
    }
}
#endif
