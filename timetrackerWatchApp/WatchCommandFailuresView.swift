import SwiftUI

struct WatchCommandFailurePresentation: Equatable, Identifiable {
    let failure: WatchFailedCommand
    let title: String

    var id: UUID {
        failure.id
    }
}

struct WatchCommandFailuresView: View {
    let failures: [WatchCommandFailurePresentation]
    let onRetryCommand: (UUID) -> Void
    let onDiscardCommand: (UUID) -> Void

    var body: some View {
        List {
            Section {
                ForEach(failures) { failure in
                    WatchCommandFailureRow(
                        title: failure.title,
                        result: failure.failure.result,
                        onRetry: { onRetryCommand(failure.id) },
                        onDiscard: { onDiscardCommand(failure.id) }
                    )
                }
            } footer: {
                Text("watch.commandFailures.footer")
            }
        }
        .navigationTitle("watch.commandFailures.listTitle")
        .navigationBarTitleDisplayMode(.inline)
    }
}
