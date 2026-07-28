import Foundation
import SwiftData

@MainActor
protocol AppleHealthReplicaReading: AnyObject {
    func snapshot(
        overlapping interval: DateInterval
    ) throws -> AppleHealthReplicaSnapshot
    func allSamples() throws -> AppleHealthReplicaSnapshot
}

@MainActor
protocol AppleHealthReplicaRepository: AppleHealthReplicaReading {
    func anchors() throws -> AppleHealthReplicaAnchors
    func apply(
        _ changes: AppleHealthReplicaChangeBatch,
        syncedAt: Date
    ) throws
    func clear() throws
}

@MainActor
final class UnavailableAppleHealthReplicaRepository:
    AppleHealthReplicaRepository
{
    private let error: Error

    init(error: Error) {
        self.error = error
    }

    func snapshot(
        overlapping _: DateInterval
    ) throws -> AppleHealthReplicaSnapshot {
        throw error
    }

    func allSamples() throws -> AppleHealthReplicaSnapshot {
        throw error
    }

    func anchors() throws -> AppleHealthReplicaAnchors {
        throw error
    }

    func apply(
        _: AppleHealthReplicaChangeBatch,
        syncedAt _: Date
    ) throws {
        throw error
    }

    func clear() throws {
        throw error
    }
}

@MainActor
final class SwiftDataAppleHealthReplicaRepository:
    AppleHealthReplicaRepository
{
    private let container: ModelContainer
    private let context: ModelContext

    init(container: ModelContainer) {
        self.container = container
        context = ModelContext(container)
        context.autosaveEnabled = false
    }

    func anchors() throws -> AppleHealthReplicaAnchors {
        let checkpoints = try context.fetch(
            FetchDescriptor<AppleHealthReplicaSchemaV1.SyncCheckpoint>()
        )
        let byStream = Dictionary(
            checkpoints.map { ($0.streamRaw, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return AppleHealthReplicaAnchors(
            workout: byStream[AppleHealthReplicaStream.workout.rawValue]?
                .anchorData,
            sleep: byStream[AppleHealthReplicaStream.sleep.rawValue]?
                .anchorData
        )
    }

    func apply(
        _ changes: AppleHealthReplicaChangeBatch,
        syncedAt: Date
    ) throws {
        try PerformanceSignpost.interval("AppleHealthReplicaApply") {
            do {
                let workouts = try canonicalWorkouts(changes.workouts)
                let sleep = try canonicalSleep(changes.sleep)
                try applyWorkoutChanges(
                    upserts: workouts,
                    deletedIDs: changes.deletedWorkoutIDs
                )
                try applySleepChanges(
                    upserts: sleep,
                    deletedIDs: changes.deletedSleepIDs
                )
                try updateCheckpoint(
                    stream: .workout,
                    anchorData: changes.workoutAnchor,
                    syncedAt: syncedAt
                )
                try updateCheckpoint(
                    stream: .sleep,
                    anchorData: changes.sleepAnchor,
                    syncedAt: syncedAt
                )
                try context.save()
            } catch {
                context.rollback()
                throw error
            }
        }
    }

    func snapshot(
        overlapping interval: DateInterval
    ) throws -> AppleHealthReplicaSnapshot {
        try PerformanceSignpost.interval("AppleHealthReplicaSnapshot") {
            guard interval.duration > 0 else {
                let status = try replicaStatus()
                return AppleHealthReplicaSnapshot(
                    samples: .empty,
                    recordCount: status.recordCount,
                    lastSuccessfulSyncAt: status.lastSuccessfulSyncAt
                )
            }
            let workouts = try workoutSamples(overlapping: interval)
            let sleep = try sleepSamples(overlapping: interval)
            let status = try replicaStatus()
            return AppleHealthReplicaSnapshot(
                samples: AppleHealthSampleBatch(
                    workouts: workouts,
                    sleep: sleep
                ),
                recordCount: status.recordCount,
                lastSuccessfulSyncAt: status.lastSuccessfulSyncAt
            )
        }
    }

    func allSamples() throws -> AppleHealthReplicaSnapshot {
        let workouts = try workoutSamples()
        let sleep = try sleepSamples()
        let status = try replicaStatus(
            workoutCount: workouts.count,
            sleepCount: sleep.count
        )
        return AppleHealthReplicaSnapshot(
            samples: AppleHealthSampleBatch(
                workouts: workouts,
                sleep: sleep
            ),
            recordCount: status.recordCount,
            lastSuccessfulSyncAt: status.lastSuccessfulSyncAt
        )
    }

    func clear() throws {
        do {
            try context.delete(
                model: AppleHealthReplicaSchemaV1.WorkoutRecord.self
            )
            try context.delete(
                model: AppleHealthReplicaSchemaV1.SleepRecord.self
            )
            try context.delete(
                model: AppleHealthReplicaSchemaV1.SyncCheckpoint.self
            )
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    private func applyWorkoutChanges(
        upserts: [AppleHealthWorkoutSample],
        deletedIDs: Set<UUID>
    ) throws {
        let affectedIDs = Set(upserts.map(\.id)).union(deletedIDs)
        let existingRecords = try workoutRecords(withIDs: affectedIDs)
        var byID = Dictionary(
            existingRecords.map { ($0.sampleID, $0) },
            uniquingKeysWith: { first, duplicate in
                context.delete(duplicate)
                return first
            }
        )
        for id in deletedIDs {
            if let record = byID.removeValue(forKey: id) {
                context.delete(record)
            }
        }
        for sample in upserts {
            if let record = byID[sample.id] {
                record.kindRaw = sample.kind.rawValue
                record.startedAt = sample.startedAt
                record.endedAt = sample.endedAt
                record.sourceBundleIdentifier =
                    sample.sourceBundleIdentifier
            } else {
                let record =
                    AppleHealthReplicaSchemaV1.WorkoutRecord(
                        sampleID: sample.id,
                        kindRaw: sample.kind.rawValue,
                        startedAt: sample.startedAt,
                        endedAt: sample.endedAt,
                        sourceBundleIdentifier:
                        sample.sourceBundleIdentifier
                    )
                context.insert(record)
                byID[sample.id] = record
            }
        }
    }

    private func applySleepChanges(
        upserts: [AppleHealthSleepSample],
        deletedIDs: Set<UUID>
    ) throws {
        let affectedIDs = Set(upserts.map(\.id)).union(deletedIDs)
        let existingRecords = try sleepRecords(withIDs: affectedIDs)
        var byID = Dictionary(
            existingRecords.map { ($0.sampleID, $0) },
            uniquingKeysWith: { first, duplicate in
                context.delete(duplicate)
                return first
            }
        )
        for id in deletedIDs {
            if let record = byID.removeValue(forKey: id) {
                context.delete(record)
            }
        }
        for sample in upserts {
            if let record = byID[sample.id] {
                record.stageRaw = sample.stage.rawValue
                record.startedAt = sample.startedAt
                record.endedAt = sample.endedAt
                record.sourceBundleIdentifier =
                    sample.sourceBundleIdentifier
                record.sourceProductType = sample.sourceProductType
            } else {
                let record = AppleHealthReplicaSchemaV1.SleepRecord(
                    sampleID: sample.id,
                    stageRaw: sample.stage.rawValue,
                    startedAt: sample.startedAt,
                    endedAt: sample.endedAt,
                    sourceBundleIdentifier:
                    sample.sourceBundleIdentifier,
                    sourceProductType: sample.sourceProductType
                )
                context.insert(record)
                byID[sample.id] = record
            }
        }
    }

    private func updateCheckpoint(
        stream: AppleHealthReplicaStream,
        anchorData: Data,
        syncedAt: Date
    ) throws {
        let streamRaw = stream.rawValue
        let descriptor = FetchDescriptor<
            AppleHealthReplicaSchemaV1.SyncCheckpoint
        >(
            predicate: #Predicate { $0.streamRaw == streamRaw }
        )
        if let checkpoint = try context.fetch(descriptor).first {
            checkpoint.anchorData = anchorData
            checkpoint.lastSuccessfulSyncAt = syncedAt
        } else {
            context.insert(
                AppleHealthReplicaSchemaV1.SyncCheckpoint(
                    streamRaw: streamRaw,
                    anchorData: anchorData,
                    lastSuccessfulSyncAt: syncedAt
                )
            )
        }
    }

    private func workoutSamples() throws -> [AppleHealthWorkoutSample] {
        try workoutSamples(
            from: context.fetch(
                FetchDescriptor<AppleHealthReplicaSchemaV1.WorkoutRecord>()
            )
        )
    }

    private func workoutSamples(
        overlapping interval: DateInterval
    ) throws -> [AppleHealthWorkoutSample] {
        let start = interval.start
        let end = interval.end
        return try workoutSamples(
            from: context.fetch(
                FetchDescriptor<AppleHealthReplicaSchemaV1.WorkoutRecord>(
                    predicate: #Predicate {
                        $0.startedAt < end && $0.endedAt > start
                    }
                )
            )
        )
    }

    private func workoutSamples(
        from records: [AppleHealthReplicaSchemaV1.WorkoutRecord]
    ) throws -> [AppleHealthWorkoutSample] {
        try records.map { record in
            guard let kind = AppleHealthWorkoutKind(
                rawValue: record.kindRaw
            ) else {
                throw AppleHealthReplicaRepositoryError
                    .invalidPersistedValue
            }
            return AppleHealthWorkoutSample(
                id: record.sampleID,
                kind: kind,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                sourceBundleIdentifier:
                record.sourceBundleIdentifier
            )
        }
    }

    private func sleepSamples() throws -> [AppleHealthSleepSample] {
        try sleepSamples(
            from: context.fetch(
                FetchDescriptor<AppleHealthReplicaSchemaV1.SleepRecord>()
            )
        )
    }

    private func sleepSamples(
        overlapping interval: DateInterval
    ) throws -> [AppleHealthSleepSample] {
        let start = interval.start
        let end = interval.end
        return try sleepSamples(
            from: context.fetch(
                FetchDescriptor<AppleHealthReplicaSchemaV1.SleepRecord>(
                    predicate: #Predicate {
                        $0.startedAt < end && $0.endedAt > start
                    }
                )
            )
        )
    }

    private func sleepSamples(
        from records: [AppleHealthReplicaSchemaV1.SleepRecord]
    ) throws -> [AppleHealthSleepSample] {
        try records.map { record in
            guard let stage = AppleHealthSleepStage(
                rawValue: record.stageRaw
            ) else {
                throw AppleHealthReplicaRepositoryError
                    .invalidPersistedValue
            }
            return AppleHealthSleepSample(
                id: record.sampleID,
                stage: stage,
                startedAt: record.startedAt,
                endedAt: record.endedAt,
                sourceBundleIdentifier:
                record.sourceBundleIdentifier,
                sourceProductType: record.sourceProductType
            )
        }
    }

    private func workoutRecords(
        withIDs ids: Set<UUID>
    ) throws -> [AppleHealthReplicaSchemaV1.WorkoutRecord] {
        guard ids.isEmpty == false else {
            return []
        }
        return try ids.chunkedForReplicaPredicate().flatMap { chunk in
            try context.fetch(
                FetchDescriptor<AppleHealthReplicaSchemaV1.WorkoutRecord>(
                    predicate: #Predicate { chunk.contains($0.sampleID) }
                )
            )
        }
    }

    private func sleepRecords(
        withIDs ids: Set<UUID>
    ) throws -> [AppleHealthReplicaSchemaV1.SleepRecord] {
        guard ids.isEmpty == false else {
            return []
        }
        return try ids.chunkedForReplicaPredicate().flatMap { chunk in
            try context.fetch(
                FetchDescriptor<AppleHealthReplicaSchemaV1.SleepRecord>(
                    predicate: #Predicate { chunk.contains($0.sampleID) }
                )
            )
        }
    }

    private func replicaStatus(
        workoutCount: Int? = nil,
        sleepCount: Int? = nil
    ) throws -> (recordCount: Int, lastSuccessfulSyncAt: Date?) {
        let resolvedWorkoutCount = try workoutCount ?? context.fetchCount(
            FetchDescriptor<AppleHealthReplicaSchemaV1.WorkoutRecord>()
        )
        let resolvedSleepCount = try sleepCount ?? context.fetchCount(
            FetchDescriptor<AppleHealthReplicaSchemaV1.SleepRecord>()
        )
        let checkpoints = try context.fetch(
            FetchDescriptor<AppleHealthReplicaSchemaV1.SyncCheckpoint>()
        )
        return (
            resolvedWorkoutCount + resolvedSleepCount,
            checkpoints.compactMap(\.lastSuccessfulSyncAt).max()
        )
    }

    private func canonicalWorkouts(
        _ samples: [AppleHealthWorkoutSample]
    ) throws -> [AppleHealthWorkoutSample] {
        for sample in samples {
            try validate(
                startedAt: sample.startedAt,
                endedAt: sample.endedAt,
                sourceBundleIdentifier:
                sample.sourceBundleIdentifier,
                sourceProductType: nil
            )
        }
        return Dictionary(grouping: samples, by: \.id)
            .values
            .compactMap { $0.max(by: workoutPreference) }
            .sorted(by: AppleHealthSampleBatch.workoutChronology)
    }

    private func canonicalSleep(
        _ samples: [AppleHealthSleepSample]
    ) throws -> [AppleHealthSleepSample] {
        for sample in samples {
            try validate(
                startedAt: sample.startedAt,
                endedAt: sample.endedAt,
                sourceBundleIdentifier:
                sample.sourceBundleIdentifier,
                sourceProductType: sample.sourceProductType
            )
        }
        return Dictionary(grouping: samples, by: \.id)
            .values
            .compactMap { $0.max(by: sleepPreference) }
            .sorted(by: AppleHealthSampleBatch.sleepChronology)
    }

    private func validate(
        startedAt: Date,
        endedAt: Date,
        sourceBundleIdentifier: String,
        sourceProductType: String?
    ) throws {
        guard startedAt <= endedAt,
              sourceBundleIdentifier.isEmpty == false,
              sourceBundleIdentifier.utf8.count <= 512,
              (sourceProductType?.utf8.count ?? 0) <= 256
        else {
            throw AppleHealthReplicaRepositoryError.invalidSample
        }
    }

    private func workoutPreference(
        _ lhs: AppleHealthWorkoutSample,
        _ rhs: AppleHealthWorkoutSample
    ) -> Bool {
        (
            lhs.startedAt,
            lhs.endedAt,
            lhs.kind.rawValue,
            lhs.sourceBundleIdentifier
        ) < (
            rhs.startedAt,
            rhs.endedAt,
            rhs.kind.rawValue,
            rhs.sourceBundleIdentifier
        )
    }

    private func sleepPreference(
        _ lhs: AppleHealthSleepSample,
        _ rhs: AppleHealthSleepSample
    ) -> Bool {
        (
            lhs.startedAt,
            lhs.endedAt,
            lhs.stage.rawValue,
            lhs.sourceBundleIdentifier,
            lhs.sourceProductType ?? ""
        ) < (
            rhs.startedAt,
            rhs.endedAt,
            rhs.stage.rawValue,
            rhs.sourceBundleIdentifier,
            rhs.sourceProductType ?? ""
        )
    }
}
