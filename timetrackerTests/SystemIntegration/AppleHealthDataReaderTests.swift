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
            _ = try await reader.authorizationRequestStatus()
        }
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

    #if DEBUG && os(iOS)
    @Test @MainActor
    func platformFactorySelectsUIFixtureAtCallTime() {
        let arguments = [
            "--uitesting",
            "--uitesting-apple-health-history",
        ]
        let reader = AppleHealthDataReaderFactory.platformDefault(
            arguments: arguments,
            environment: [:]
        )
        let reusedReader = AppleHealthDataReaderFactory.platformDefault(
            arguments: arguments,
            environment: [:]
        )

        #expect(reader is UITestAppleHealthDataReader)
        #expect(reader === reusedReader)
    }

    @Test @MainActor
    func uiFixtureRequiresUITestLaunchAndExplicitOptIn() throws {
        #expect(
            UITestAppleHealthDataReader.makeIfRequested(
                arguments: ["--uitesting-apple-health"],
                environment: [:]
            ) == nil
        )
        #expect(
            UITestAppleHealthDataReader.makeIfRequested(
                arguments: ["--uitesting"],
                environment: [:]
            ) == nil
        )
        let arguments = ["--uitesting", "--uitesting-apple-health"]
        _ = try #require(
            UITestAppleHealthDataReader.makeIfRequested(
                arguments: arguments,
                environment: [:]
            )
        )
        let preferences = try #require(
            UITestAppleHealthDataReader.preferenceStoreIfRequested(
                arguments: arguments,
                environment: [:]
            )
        )
        preferences.isTimelineEnabled = true
        let freshPreferences = try #require(
            UITestAppleHealthDataReader.preferenceStoreIfRequested(
                arguments: arguments,
                environment: [:]
            )
        )

        #expect(freshPreferences.isTimelineEnabled == false)
        #expect(freshPreferences.taskCatalogClearRecoveryTaskIDs.isEmpty)

        let environment = ["TIMETRACKER_UI_TEST_APPLE_HEALTH": "1"]
        _ = try #require(
            UITestAppleHealthDataReader.makeIfRequested(
                arguments: ["--uitesting"],
                environment: environment
            )
        )
        #expect(
            UITestAppleHealthDataReader.makeIfRequested(
                arguments: [],
                environment: environment
            ) == nil
        )
    }

    @Test @MainActor
    func uiFixtureKeepsWorkoutAndSleepVisibleBeforeNoon() async throws {
        let reader = try #require(
            UITestAppleHealthDataReader.makeIfRequested(
                arguments: ["--uitesting", "--uitesting-apple-health"]
            )
        )
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: Date())

        for elapsed in [1.0, 60.0, 6 * 3600.0] {
            let visibleEnd = dayStart.addingTimeInterval(elapsed)
            let visibleInterval = DateInterval(
                start: dayStart,
                end: visibleEnd
            )
            let queryInterval = DateInterval(
                start: dayStart.addingTimeInterval(
                    -AppleHealthSleepEpisodePolicy.queryContextDuration
                ),
                end: visibleEnd
            )
            let batch = try await reader.samples(overlapping: queryInterval)
            let items = AppleHealthTimelineProjectionService().project(
                batch: batch,
                visibleInterval: visibleInterval
            )

            #expect(items.count == 2)
            #expect(items.contains { $0.subject == .appleHealthSleep })
            #expect(
                items.contains {
                    $0.subject == .appleHealthWorkout(.running)
                }
            )
            #expect(
                items.allSatisfy {
                    $0.interval.start >= visibleInterval.start &&
                        $0.interval.end <= visibleInterval.end
                }
            )
        }
    }
    #endif

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
        let mappings: [
            (HKCategoryValueSleepAnalysis, AppleHealthSleepStage)
        ] = [
            (.inBed, .inBed),
            (.awake, .awake),
            (.asleepUnspecified, .asleepUnspecified),
            (.asleepCore, .asleepCore),
            (.asleepDeep, .asleepDeep),
            (.asleepREM, .asleepREM),
        ]

        for (healthKitValue, expectedStage) in mappings {
            #expect(
                HealthKitAppleHealthDataReader.sleepStage(
                    for: healthKitValue.rawValue
                ) == expectedStage
            )
        }
        #expect(HealthKitAppleHealthDataReader.sleepStage(for: .max) == nil)
    }

    @Test @MainActor
    func healthKitAuthorizationRequestStatusMapsWithoutRevealingReadAccess() {
        #expect(
            HealthKitAppleHealthDataReader.authorizationRequestStatus(
                for: .unknown
            ) == .unknown
        )
        #expect(
            HealthKitAppleHealthDataReader.authorizationRequestStatus(
                for: .shouldRequest
            ) == .shouldRequest
        )
        #expect(
            HealthKitAppleHealthDataReader.authorizationRequestStatus(
                for: .unnecessary
            ) == .unnecessary
        )
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
        #expect(reader.contains("statusForAuthorizationRequest("))
        #expect(reader.contains("HKObjectType.workoutType()"))
        #expect(reader.contains(".sleepAnalysis"))
        #expect(reader.contains("authorizationStatus(for:") == false)
        #expect(reader.contains("healthStore.save(") == false)
    }

    @Test
    func healthSamplesAreNotAddedToCloudSyncedModels() throws {
        let persistenceSources = try [
            "timetracker/Models/TimeTrackerModelRegistry.swift",
            "timetracker/Models/SchemaModels.swift",
            "timetracker/Models/LedgerModels.swift",
            "timetracker/Repositories/RepositoryProtocols.swift",
            "timetracker/Repositories/SwiftDataTaskRepository.swift",
            "timetracker/Repositories/SwiftDataTimeTrackingRepository.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+Capture.swift",
            "timetracker/Services/SystemIntegration/SyncDataSnapshot+Restore.swift",
        ].map(sourceText).joined(separator: "\n")
        let preferenceSource = try sourceText(
            "timetracker/Models/SyncedPreferences.swift"
        )
        let syncedPreferenceKeys = try #require(
            preferenceSource.slice(
                from: "enum AppPreferenceKey",
                to: "enum AppLocalPreferenceKey"
            )
        )
        let localPreferenceKeys = try #require(
            preferenceSource.slice(
                from: "enum AppLocalPreferenceKey",
                to: "struct AppPreferences"
            )
        )

        #expect(persistenceSources.contains("AppleHealth") == false)
        #expect(persistenceSources.contains("HealthKit") == false)
        #expect(
            syncedPreferenceKeys.contains("appleHealthTimelineEnabled") == false
        )
        #expect(localPreferenceKeys.contains("appleHealthTimelineEnabled"))
    }

    private func entitlements(at url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let value = try PropertyListSerialization.propertyList(from: data, format: nil)
        return try #require(value as? [String: Any])
    }
}
