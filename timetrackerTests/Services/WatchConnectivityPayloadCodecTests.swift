import Foundation
import Testing
@testable import timetracker

struct WatchConnectivityPayloadCodecTests {
    private let now = Date()

    @Test
    func startCommandRoundTrips() {
        let command = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: UUID(),
            segmentID: nil,
            issuedAt: now,
            deviceID: "watch-a"
        )

        #expect(WatchConnectivityPayloadCodec.decodeCommand(
            from: WatchConnectivityPayloadCodec.encode(command: command)
        ) == command)
    }

    @Test
    func stopCommandRoundTrips() {
        let command = WatchTimerCommand(
            id: UUID(),
            type: .stopSegment,
            taskID: nil,
            segmentID: UUID(),
            issuedAt: now,
            deviceID: "watch-b"
        )

        #expect(WatchConnectivityPayloadCodec.decodeCommand(
            from: WatchConnectivityPayloadCodec.encode(command: command)
        ) == command)
    }

    @Test
    func terminalResultRoundTrips() {
        let result = WatchCommandResult(
            commandID: UUID(),
            status: .missingTask,
            completedAt: now,
            relatedID: UUID(),
            failureCode: "missing"
        )

        #expect(WatchConnectivityPayloadCodec.decodeCommandResult(
            from: WatchConnectivityPayloadCodec.encode(result: result)
        ) == result)
    }

    @Test
    func rankedStateSnapshotRoundTrips() {
        let active = WatchActiveTimerSnapshot(
            id: UUID(),
            taskID: UUID(),
            title: "Active",
            path: "Root / Active",
            startedAt: now.addingTimeInterval(-60),
            colorHex: "1677FF",
            iconName: "timer"
        )
        let recent = WatchRecentTaskSnapshot(
            taskID: UUID(),
            title: "Recent",
            path: "Root / Recent",
            colorHex: "7C3AED",
            iconName: "checkmark",
            quickStartRank: 0,
            allTasksRank: 0
        )
        let state = WatchStateSnapshot(
            generatedAt: now,
            todayGrossSeconds: 600,
            todayWallSeconds: 540,
            activeTimers: [active],
            recentTasks: [recent]
        )

        #expect(WatchConnectivityPayloadCodec.decodeState(
            from: WatchConnectivityPayloadCodec.encode(state: state)
        ) == state)
    }

    @Test
    func decoderRejectsInvalidCommandsAndOversizedSnapshots() {
        let invalidCommand = WatchTimerCommand(
            id: UUID(),
            type: .startTask,
            taskID: nil,
            segmentID: nil,
            issuedAt: now,
            deviceID: "watch"
        )
        let recentTasks = (0 ... WatchTransportLimits.maximumRecentTasks).map { index in
            WatchRecentTaskSnapshot(
                taskID: UUID(),
                title: "Task \(index)",
                path: "Task \(index)",
                colorHex: nil,
                iconName: nil
            )
        }
        let oversized = WatchStateSnapshot(
            generatedAt: now,
            todayGrossSeconds: 0,
            todayWallSeconds: 0,
            activeTimers: [],
            recentTasks: recentTasks
        )

        #expect(WatchConnectivityPayloadCodec.decodeCommand(
            from: WatchConnectivityPayloadCodec.encode(command: invalidCommand)
        ) == nil)
        #expect(WatchConnectivityPayloadCodec.decodeState(
            from: WatchConnectivityPayloadCodec.encode(state: oversized)
        ) == nil)
    }
}
