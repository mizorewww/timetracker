import Foundation

struct WatchRowCommandPresentation: Equatable {
    let state: WatchRowCommandState
    let retryCommandID: UUID?
}

struct WatchCommandPresentationIndex: Equatable {
    private let pendingStartTaskIDs: Set<UUID>
    private let pendingStopSegmentIDs: Set<UUID>
    private let failedStartCommandIDs: [UUID: UUID]
    private let failedStopCommandIDs: [UUID: UUID]

    init(
        pendingCommands: [WatchTimerCommand],
        failedCommands: [WatchFailedCommand]
    ) {
        pendingStartTaskIDs = Set(pendingCommands.compactMap { command in
            command.type == .startTask ? command.taskID : nil
        })
        pendingStopSegmentIDs = Set(pendingCommands.compactMap { command in
            command.type == .stopSegment ? command.segmentID : nil
        })

        var failedStarts: [UUID: UUID] = [:]
        var failedStops: [UUID: UUID] = [:]
        for failure in failedCommands {
            switch failure.command.type {
            case .startTask:
                if let taskID = failure.command.taskID {
                    failedStarts[taskID] = failure.id
                }
            case .stopSegment:
                if let segmentID = failure.command.segmentID {
                    failedStops[segmentID] = failure.id
                }
            }
        }
        failedStartCommandIDs = failedStarts
        failedStopCommandIDs = failedStops
    }

    func startTask(_ taskID: UUID) -> WatchRowCommandPresentation {
        presentation(
            isPending: pendingStartTaskIDs.contains(taskID),
            retryCommandID: failedStartCommandIDs[taskID]
        )
    }

    func stopTimer(_ segmentID: UUID) -> WatchRowCommandPresentation {
        presentation(
            isPending: pendingStopSegmentIDs.contains(segmentID),
            retryCommandID: failedStopCommandIDs[segmentID]
        )
    }

    private func presentation(
        isPending: Bool,
        retryCommandID: UUID?
    ) -> WatchRowCommandPresentation {
        let state: WatchRowCommandState = if isPending {
            .pending
        } else if retryCommandID != nil {
            .failed
        } else {
            .idle
        }
        return WatchRowCommandPresentation(state: state, retryCommandID: retryCommandID)
    }
}
