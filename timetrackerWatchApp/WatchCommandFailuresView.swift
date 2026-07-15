import SwiftUI

struct WatchCommandFailurePresentation: Equatable, Identifiable {
    let failure: WatchFailedCommand
    let title: String

    var id: UUID { failure.id }
}

struct WatchCommandFailuresView: View {
    let failures: [WatchCommandFailurePresentation]
    let onRetryCommand: (UUID) -> Void
    let onDiscardCommand: (UUID) -> Void

    var body: some View {
        List {
            Section {
                ForEach(failures) { failure in
                    WatchCommandFailureActionRow(
                        failure: failure,
                        onRetryCommand: onRetryCommand,
                        onDiscardCommand: onDiscardCommand
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

struct WatchCommandFailureActionRow: View {
    let failure: WatchCommandFailurePresentation
    let onRetryCommand: (UUID) -> Void
    let onDiscardCommand: (UUID) -> Void

    var body: some View {
        WatchCommandFailureRow(
            title: failure.title,
            result: failure.failure.result,
            onRetry: { onRetryCommand(failure.id) },
            onDiscard: { onDiscardCommand(failure.id) }
        )
    }
}
