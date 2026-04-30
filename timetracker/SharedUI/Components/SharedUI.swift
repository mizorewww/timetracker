import SwiftData
import SwiftUI

#Preview {
    ContentView()
        .modelContainer(for: TimeTrackerModelRegistry.currentModels, inMemory: true)
}
