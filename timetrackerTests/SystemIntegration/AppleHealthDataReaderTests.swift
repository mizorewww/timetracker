import Foundation
import Testing
@testable import timetracker

#if os(iOS) && canImport(HealthKit)
import HealthKit
#endif

@Suite(.serialized)
struct AppleHealthDataReaderTests {
    @Test @MainActor
    func unsupportedPlatformsFailWithoutPretendingPermissionWasDenied() async {
        let reader = UnavailableAppleHealthDataReader()
        #expect(reader.isHealthDataAvailable == false)

        await #expect(throws: AppleHealthReadError.unavailable) {
            try await reader.requestReadAuthorization()
        }
        await #expect(throws: AppleHealthReadError.unavailable) {
            try await reader.samples(
                overlapping: DateInterval(start: .now, duration: 60)
            )
        }
    }

    @Test
    func sleepStagesSeparateActualSleepFromInBedAndAwake() {
        #expect(AppleHealthSleepStage.asleepUnspecified.isAsleep)
        #expect(AppleHealthSleepStage.asleepCore.isAsleep)
        #expect(AppleHealthSleepStage.asleepDeep.isAsleep)
        #expect(AppleHealthSleepStage.asleepREM.isAsleep)
        #expect(AppleHealthSleepStage.inBed.isAsleep == false)
        #expect(AppleHealthSleepStage.awake.isAsleep == false)
    }

    @Test
    func sampleBatchesHaveDeterministicChronology() throws {
        let earlyID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        let lateID = try #require(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        let start = Date(timeIntervalSince1970: 100)
        let workout = { (id: UUID, offset: TimeInterval) in
            AppleHealthWorkoutSample(
                id: id,
                kind: .walking,
                startedAt: start.addingTimeInterval(offset),
                endedAt: start.addingTimeInterval(offset + 30),
                sourceBundleIdentifier: "test"
            )
        }
        let sleep = { (id: UUID, offset: TimeInterval) in
            AppleHealthSleepSample(
                id: id,
                stage: .asleepCore,
                startedAt: start.addingTimeInterval(offset),
                endedAt: start.addingTimeInterval(offset + 30),
                sourceBundleIdentifier: "test"
            )
        }

        let batch = AppleHealthSampleBatch(
            workouts: [workout(lateID, 60), workout(earlyID, 0)],
            sleep: [sleep(lateID, 60), sleep(earlyID, 0)]
        )

        #expect(batch.workouts.map(\.id) == [earlyID, lateID])
        #expect(batch.sleep.map(\.id) == [earlyID, lateID])
    }

    @Test @MainActor
    func platformFactoryReusesItsLongLivedReader() {
        let first = AppleHealthDataReaderFactory.platformDefault()
        let second = AppleHealthDataReaderFactory.platformDefault()

        #expect(first === second)
    }

    #if os(iOS) && canImport(HealthKit)
    @Test @MainActor
    func healthKitActivityTypesMapToProductKinds() {
        #expect(HealthKitAppleHealthDataReader.workoutKind(for: .walking) == .walking)
        #expect(HealthKitAppleHealthDataReader.workoutKind(for: .running) == .running)
        #expect(HealthKitAppleHealthDataReader.workoutKind(for: .functionalStrengthTraining) == .strengthTraining)
        #expect(HealthKitAppleHealthDataReader.workoutKind(for: .socialDance) == .dance)
        #expect(HealthKitAppleHealthDataReader.workoutKind(for: .cardioDance) == .dance)
        #expect(HealthKitAppleHealthDataReader.workoutKind(for: .americanFootball) == .other)
    }

    @Test @MainActor
    func healthKitSleepValuesMapWithoutInventingUnknownStages() {
        #expect(
            HealthKitAppleHealthDataReader.sleepStage(
                for: HKCategoryValueSleepAnalysis.asleepCore.rawValue
            ) == .asleepCore
        )
        #expect(
            HealthKitAppleHealthDataReader.sleepStage(
                for: HKCategoryValueSleepAnalysis.awake.rawValue
            ) == .awake
        )
        #expect(HealthKitAppleHealthDataReader.sleepStage(for: .max) == nil)
    }
    #endif

    @Test
    func readAccessStaysMinimalAndSigningIsPlatformSpecific() throws {
        let project = try sourceText("timetracker.xcodeproj/project.pbxproj")
        let root = try projectRootURL()
        let iosEntitlements = try entitlements(
            at: root.appending(path: "timetracker/timetracker-iOS.entitlements")
        )
        let macEntitlements = try entitlements(
            at: root.appending(path: "timetracker/timetracker.entitlements")
        )
        let info = try sourceText("timetracker/Info.plist")
        let reader = try sourceText(
            "timetracker/Services/SystemIntegration/AppleHealthDataReader.swift"
        )

        #expect(project.contains("\"CODE_SIGN_ENTITLEMENTS[sdk=iphoneos*]\" = \"timetracker/timetracker-iOS.entitlements\""))
        #expect(project.contains("\"CODE_SIGN_ENTITLEMENTS[sdk=iphonesimulator*]\" = \"timetracker/timetracker-iOS.entitlements\""))
        #expect(project.contains("\"CODE_SIGN_STYLE[sdk=iphoneos*]\" = Manual"))
        #expect(project.contains("\"PROVISIONING_PROFILE_SPECIFIER[sdk=iphoneos*]\" = \"TimeTracker HealthKit Development\""))
        #expect(iosEntitlements["com.apple.developer.healthkit"] as? Bool == true)
        #expect(iosEntitlements["com.apple.developer.healthkit.background-delivery"] == nil)
        #expect(iosEntitlements["com.apple.developer.healthkit.access"] == nil)
        #expect(macEntitlements["com.apple.developer.healthkit"] == nil)
        #expect(info.contains("NSHealthShareUsageDescription"))
        #expect(info.contains("NSHealthUpdateUsageDescription") == false)
        #expect(reader.contains("requestAuthorization(toShare: [], read: types)"))
        #expect(reader.contains("HKObjectType.workoutType()"))
        #expect(reader.contains(".sleepAnalysis"))
        #expect(reader.contains("authorizationStatus(for:") == false)
        #expect(reader.contains("healthStore.save(") == false)
    }

    @Test
    func healthSamplesAreNotAddedToCloudSyncedModels() throws {
        let registry = try sourceText("timetracker/Models/TimeTrackerModelRegistry.swift")
        let ledger = try sourceText("timetracker/Models/LedgerModels.swift")

        #expect(registry.contains("AppleHealth") == false)
        #expect(ledger.contains("AppleHealth") == false)
        #expect(ledger.contains("HealthKit") == false)
    }

    private func entitlements(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(value as? [String: Any])
    }
}
