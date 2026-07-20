import Foundation
import SwiftData
import Testing
@testable import timetracker

@Suite(.serialized)
struct PreferencesChecklistForecastTests {
    @Test @MainActor
    func newerPreferenceTombstoneSuppressesOlderActiveDuplicate() {
        let key = AppPreferenceKey.defaultFocusMinutes.rawValue
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        let oldActive = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(90),
            deviceID: "old"
        )
        oldActive.createdAt = base
        oldActive.updatedAt = base

        let newerTombstone = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(90),
            deviceID: "new"
        )
        newerTombstone.createdAt = base.addingTimeInterval(10)
        newerTombstone.updatedAt = base.addingTimeInterval(10)
        newerTombstone.deletedAt = newerTombstone.updatedAt

        let preferences = AppPreferences(syncedPreferences: [oldActive, newerTombstone])

        #expect(preferences.defaultFocusMinutes == AppPreferences.defaults.defaultFocusMinutes)
    }

    @Test @MainActor
    func preferenceLogicalKeyTieBreakIsStableAcrossFetchOrder() {
        let key = AppPreferenceKey.defaultFocusMinutes.rawValue
        let timestamp = Date(timeIntervalSinceReferenceDate: 100_000)
        let lowerID = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(25),
            deviceID: "first"
        )
        lowerID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        lowerID.createdAt = timestamp
        lowerID.updatedAt = timestamp
        let higherID = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(50),
            deviceID: "second"
        )
        higherID.id = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        higherID.createdAt = timestamp
        higherID.updatedAt = timestamp

        let forward = SyncedPreferenceService.latestByKey([lowerID, higherID])[key]
        let reverse = SyncedPreferenceService.latestByKey([higherID, lowerID])[key]

        #expect(forward === higherID)
        #expect(reverse === higherID)
    }

    @Test @MainActor
    func corruptedSyncedPreferencesAreNormalizedAndBounded() {
        let repeatedID = UUID()
        let planValues = (0..<40).map { index in
            PomodoroPlan(
                id: index < 2 ? repeatedID : UUID(),
                name: String(repeating: "p", count: 200),
                focusMinutes: 25
            )
        }
        let quickStartValues = (0..<40).map { _ in UUID() }
        let heatmapValues = (0..<80).map { _ in UUID() }
        let modelValues = (0..<300).map { " model-\($0) " } + ["model-1", "   "]
        let preferences = AppPreferences(syncedPreferences: [
            SyncedPreference(
                key: AppPreferenceKey.preferredColorScheme.rawValue,
                valueJSON: PreferenceJSON.encode("neon"),
                deviceID: "remote"
            ),
            SyncedPreference(
                key: AppPreferenceKey.pomodoroDefaultMode.rawValue,
                valueJSON: PreferenceJSON.encode("unknown"),
                deviceID: "remote"
            ),
            SyncedPreference(
                key: AppPreferenceKey.pomodoroPlans.rawValue,
                valueJSON: PreferenceJSON.encode(planValues),
                deviceID: "remote"
            ),
            SyncedPreference(
                key: AppPreferenceKey.quickStartTaskIDs.rawValue,
                valueJSON: PreferenceJSON.encode(
                    (quickStartValues + [quickStartValues[0]]).map(\.uuidString) + ["not-a-uuid"]
                ),
                deviceID: "remote"
            ),
            SyncedPreference(
                key: AppPreferenceKey.todayHeatmapTaskIDs.rawValue,
                valueJSON: PreferenceJSON.encode(
                    (heatmapValues + [heatmapValues[0]]).map(\.uuidString) + ["not-a-uuid"]
                ),
                deviceID: "remote"
            ),
            SyncedPreference(
                key: AppPreferenceKey.llmEndpoint.rawValue,
                valueJSON: PreferenceJSON.encode("  https://example.test/" + String(repeating: "a", count: 3_000)),
                deviceID: "remote"
            ),
            SyncedPreference(
                key: AppPreferenceKey.llmSelectedModel.rawValue,
                valueJSON: PreferenceJSON.encode("stale-model"),
                deviceID: "remote"
            ),
            SyncedPreference(
                key: AppPreferenceKey.llmAvailableModelIDs.rawValue,
                valueJSON: PreferenceJSON.encode(modelValues),
                deviceID: "remote"
            )
        ])

        #expect(preferences.preferredColorScheme == "system")
        #expect(preferences.pomodoroDefaultMode == PomodoroPreset.classic.rawValue)
        #expect(preferences.pomodoroPlans.count == AppPreferenceValueSanitizer.maximumPomodoroPlanCount)
        #expect(Set(preferences.pomodoroPlans.map(\.id)).count == preferences.pomodoroPlans.count)
        #expect(preferences.pomodoroPlans.allSatisfy {
            $0.name.count <= AppPreferenceValueSanitizer.maximumPomodoroPlanNameLength
        })
        #expect(preferences.quickStartTaskIDs == Array(
            quickStartValues.prefix(AppPreferenceValueSanitizer.maximumQuickStartTaskCount)
        ))
        #expect(preferences.todayHeatmapTaskIDs == Array(
            heatmapValues.prefix(AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount)
        ))
        #expect(preferences.llmEndpoint.count <= AppPreferenceValueSanitizer.maximumLLMEndpointLength)
        #expect(preferences.llmEndpoint.hasPrefix("https://example.test/"))
        #expect(preferences.llmAvailableModelIDs.count == AppPreferenceValueSanitizer.maximumLLMModelCount)
        #expect(preferences.llmAvailableModelIDs == preferences.llmAvailableModelIDs.sorted())
        #expect(preferences.llmSelectedModel.isEmpty)

        let oversizedJSON = "\"" + String(
            repeating: "x",
            count: PreferenceJSON.maximumPayloadByteCount + 1
        ) + "\""
        #expect(PreferenceJSON.decode(String.self, from: oversizedJSON, default: "fallback") == "fallback")
    }

    @Test @MainActor
    func heatmapPreferenceJSONCanonicalizesInvalidDuplicateAndOversizedSelections() throws {
        let taskIDs = (0..<(AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount + 2))
            .map { _ in UUID() }
        let rawValues = [
            taskIDs[0].uuidString.lowercased(),
            "not-a-uuid",
            taskIDs[0].uuidString
        ] + taskIDs.dropFirst().map(\.uuidString)

        let canonicalJSON = try PreferenceJSON.canonicalValueJSON(
            for: .todayHeatmapTaskIDs,
            from: PreferenceJSON.encode(rawValues)
        )
        let canonicalValues = try PreferenceJSON.decodeChecked(
            [String].self,
            from: canonicalJSON
        )

        #expect(
            canonicalValues ==
                Array(
                    taskIDs.prefix(
                        AppPreferenceValueSanitizer.maximumTodayHeatmapTaskCount
                    )
                )
                .map(\.uuidString)
        )
    }

    @Test @MainActor
    func preferenceStoreFetchIncludesTombstonesBeforeResolvingLogicalKeys() throws {
        let defaults = UserDefaults.standard
        let previousMigration = defaults.object(forKey: SyncedPreferenceService.migrationKey)
        defer {
            if let previousMigration {
                defaults.set(previousMigration, forKey: SyncedPreferenceService.migrationKey)
            } else {
                defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
            }
        }
        defaults.set(true, forKey: SyncedPreferenceService.migrationKey)

        let context = try makeTestContext()
        let key = AppPreferenceKey.defaultFocusMinutes.rawValue
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        let oldActive = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(90),
            deviceID: "old"
        )
        oldActive.createdAt = base
        oldActive.updatedAt = base
        let newerTombstone = SyncedPreference(
            key: key,
            valueJSON: PreferenceJSON.encode(90),
            deviceID: "new"
        )
        newerTombstone.createdAt = base.addingTimeInterval(10)
        newerTombstone.updatedAt = base.addingTimeInterval(10)
        newerTombstone.deletedAt = newerTombstone.updatedAt
        context.insert(oldActive)
        context.insert(newerTombstone)
        try context.save()

        let store = makeTestStore(llmCredentialStore: TestLLMCredentialStore())
        store.configureIfNeeded(context: context)

        #expect(store.preferences.defaultFocusMinutes == AppPreferences.defaults.defaultFocusMinutes)
        #expect(try store.fetchSyncedPreferences().contains { $0.key == key } == false)
    }

    @Test @MainActor
    func sensitivePreferenceMigrationDoesNotResurrectAKeyBehindANewerTombstone() throws {
        let context = try makeTestContext()
        let base = Date(timeIntervalSinceReferenceDate: 100_000)
        let oldActive = SyncedPreference(
            key: SyncedPreferenceService.legacyLLMAPIKey,
            valueJSON: PreferenceJSON.encode("old-secret"),
            deviceID: "old"
        )
        oldActive.createdAt = base
        oldActive.updatedAt = base
        let newerTombstone = SyncedPreference(
            key: SyncedPreferenceService.legacyLLMAPIKey,
            valueJSON: PreferenceJSON.encode(""),
            deviceID: "new"
        )
        newerTombstone.createdAt = base.addingTimeInterval(10)
        newerTombstone.updatedAt = base.addingTimeInterval(10)
        newerTombstone.deletedAt = newerTombstone.updatedAt
        context.insert(oldActive)
        context.insert(newerTombstone)
        try context.save()
        let credentialStore = TestLLMCredentialStore()

        try SyncedPreferenceService.migrateSensitivePreferences(
            context: context,
            credentialStore: credentialStore,
            now: base.addingTimeInterval(20),
            deviceID: "migration"
        )

        #expect(try credentialStore.readAPIKey() == nil)
        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        #expect(stored.allSatisfy { $0.deletedAt != nil })
        #expect(stored.allSatisfy {
            PreferenceJSON.decode(String.self, from: $0.valueJSON, default: "unexpected").isEmpty
        })
    }

    @Test @MainActor
    func syncedPreferenceMigrationImportsLegacyUserDefaults() throws {
        let defaults = UserDefaults.standard
        let keys = AppPreferenceKey.allCases.map(\.rawValue) + [
            AppCloudSync.enabledKey,
            SyncedPreferenceService.migrationKey,
            SyncedPreferenceService.legacyLLMAPIKey
        ]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in previousValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        let pinnedID = UUID()
        defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
        defaults.set("dark", forKey: AppPreferenceKey.preferredColorScheme.rawValue)
        defaults.set("deep", forKey: AppPreferenceKey.pomodoroDefaultMode.rawValue)
        defaults.set(50, forKey: AppPreferenceKey.defaultFocusMinutes.rawValue)
        defaults.set(10, forKey: AppPreferenceKey.defaultBreakMinutes.rawValue)
        defaults.set(4, forKey: AppPreferenceKey.defaultPomodoroRounds.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.allowParallelTimers.rawValue)
        defaults.set(false, forKey: AppPreferenceKey.showGrossAndWallTogether.rawValue)
        defaults.set(false, forKey: AppCloudSync.enabledKey)
        defaults.set(pinnedID.uuidString, forKey: AppPreferenceKey.quickStartTaskIDs.rawValue)
        defaults.set("https://example.test/v1", forKey: AppPreferenceKey.llmEndpoint.rawValue)
        defaults.set("test-key", forKey: SyncedPreferenceService.legacyLLMAPIKey)
        defaults.set("gpt-test", forKey: AppPreferenceKey.llmSelectedModel.rawValue)
        defaults.set("gpt-test,gpt-other", forKey: AppPreferenceKey.llmAvailableModelIDs.rawValue)
        defaults.set(
            "Prefer concise generated tasks.",
            forKey: AppPreferenceKey.llmTaskPlanInstructions.rawValue
        )

        let context = try makeTestContext()
        let credentialStore = TestLLMCredentialStore()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(context: context, deviceID: "test")
        try SyncedPreferenceService.migrateSensitivePreferences(
            context: context,
            credentialStore: credentialStore,
            deviceID: "test"
        )
        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        var preferences = AppPreferences(syncedPreferences: stored)
        preferences.llmAPIKey = try credentialStore.readAPIKey() ?? ""

        #expect(stored.count == AppPreferenceKey.allCases.count - 2)
        #expect(stored.allSatisfy { SyncedPreferenceService.shouldSyncKey($0.key) })
        #expect(preferences.preferredColorScheme == "dark")
        #expect(preferences.pomodoroDefaultMode == PomodoroPreset.deep.rawValue)
        #expect(preferences.defaultFocusMinutes == 50)
        #expect(preferences.defaultBreakMinutes == 10)
        #expect(preferences.defaultPomodoroRounds == 4)
        #expect(preferences.allowParallelTimers == false)
        #expect(preferences.showGrossAndWallTogether == false)
        #expect(preferences.cloudSyncEnabled == false)
        #expect(preferences.quickStartTaskIDs == [pinnedID])
        #expect(preferences.todayHeatmapTaskIDs.isEmpty)
        #expect(preferences.llmEndpoint == "https://example.test/v1")
        #expect(preferences.llmAPIKey == "test-key")
        #expect(preferences.llmSelectedModel == "gpt-test")
        #expect(preferences.llmAvailableModelIDs == ["gpt-other", "gpt-test"])
        #expect(preferences.llmTaskPlanInstructions == "Prefer concise generated tasks.")
        let defaultPlans = PomodoroPlan.defaultPlans
        #expect(preferences.pomodoroPlans.map(\.name) == defaultPlans.map(\.name))
        #expect(preferences.pomodoroPlans.map(\.iconName) == defaultPlans.map(\.iconName))
        #expect(preferences.pomodoroPlans.map(\.colorHex) == defaultPlans.map(\.colorHex))
        #expect(preferences.pomodoroPlans.map(\.focusMinutes) == defaultPlans.map(\.focusMinutes))
        #expect(preferences.pomodoroPlans.map(\.shortBreakMinutes) == defaultPlans.map(\.shortBreakMinutes))
        #expect(preferences.pomodoroPlans.map(\.longBreakMinutes) == defaultPlans.map(\.longBreakMinutes))
        #expect(preferences.pomodoroPlans.map(\.rounds) == defaultPlans.map(\.rounds))
    }

    @Test @MainActor
    func freshDeviceMigrationDoesNotPersistDefaultsAheadOfCloudImport() throws {
        let defaults = UserDefaults.standard
        let keys = AppPreferenceKey.allCases.map(\.rawValue) + [SyncedPreferenceService.migrationKey]
        let previousValues = Dictionary(uniqueKeysWithValues: keys.map { ($0, defaults.object(forKey: $0)) })
        defer {
            for (key, value) in previousValues {
                if let value {
                    defaults.set(value, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }
        for key in keys {
            defaults.removeObject(forKey: key)
        }

        let context = try makeTestContext()
        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(context: context, deviceID: "fresh-device")
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).isEmpty)

        let cloudPreference = SyncedPreference(
            key: AppPreferenceKey.defaultFocusMinutes.rawValue,
            valueJSON: PreferenceJSON.encode(55),
            deviceID: "existing-device"
        )
        cloudPreference.updatedAt = Date(timeIntervalSinceReferenceDate: 1)
        context.insert(cloudPreference)
        try context.save()

        let preferences = AppPreferences(
            syncedPreferences: try context.fetch(FetchDescriptor<SyncedPreference>())
        )
        #expect(preferences.defaultFocusMinutes == 55)
    }

    @Test @MainActor
    func legacyPreferenceMigrationDoesNotResurrectAKeyBehindATombstone() throws {
        let defaults = UserDefaults.standard
        let preferenceKey = AppPreferenceKey.defaultFocusMinutes.rawValue
        let previousPreference = defaults.object(forKey: preferenceKey)
        let previousMigration = defaults.object(forKey: SyncedPreferenceService.migrationKey)
        defer {
            if let previousPreference {
                defaults.set(previousPreference, forKey: preferenceKey)
            } else {
                defaults.removeObject(forKey: preferenceKey)
            }
            if let previousMigration {
                defaults.set(previousMigration, forKey: SyncedPreferenceService.migrationKey)
            } else {
                defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
            }
        }

        defaults.set(90, forKey: preferenceKey)
        defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)

        let context = try makeTestContext()
        let deletedAt = Date(timeIntervalSinceReferenceDate: 100_000)
        let tombstone = SyncedPreference(
            key: preferenceKey,
            valueJSON: PreferenceJSON.encode(50),
            deviceID: "remote"
        )
        tombstone.createdAt = deletedAt
        tombstone.updatedAt = deletedAt
        tombstone.deletedAt = deletedAt
        context.insert(tombstone)
        try context.save()

        try SyncedPreferenceService.migrateLegacyPreferencesIfNeeded(
            context: context,
            deviceID: "migration"
        )

        let stored = try context.fetch(FetchDescriptor<SyncedPreference>())
        #expect(stored.filter { $0.key == preferenceKey }.count == 1)
        #expect(AppPreferences(syncedPreferences: stored).defaultFocusMinutes == 25)
    }

    @Test @MainActor
    func settingsWriteSyncedPreferencesAndDeviceLocalCloudSetting() throws {
        let defaults = UserDefaults.standard
        let previousMigration = defaults.object(forKey: SyncedPreferenceService.migrationKey)
        let previousCloud = defaults.object(forKey: AppCloudSync.enabledKey)
        let cloudRecoveryKeys = [
            AppCloudSync.pendingCloudUploadResetKey,
            AppCloudSync.pendingCloudDownloadResetKey,
            AppCloudSync.queuedCloudReconciliationKey,
            AppCloudSync.activeCloudReconciliationKey,
            AppCloudSync.cloudRecoveryStoreResetKey,
            AppCloudSync.activeCloudDownloadRecoveryKey,
        ]
        let previousCloudRecoveryValues = Dictionary(
            uniqueKeysWithValues: cloudRecoveryKeys.map { ($0, defaults.object(forKey: $0)) }
        )
        cloudRecoveryKeys.forEach { defaults.removeObject(forKey: $0) }
        let previousAutomaticSuggestions = defaults.object(
            forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
        )
        defer {
            if let previousMigration {
                defaults.set(previousMigration, forKey: SyncedPreferenceService.migrationKey)
            } else {
                defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
            }
            if let previousCloud {
                defaults.set(previousCloud, forKey: AppCloudSync.enabledKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.enabledKey)
            }
            if let previousAutomaticSuggestions {
                defaults.set(
                    previousAutomaticSuggestions,
                    forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
                )
            } else {
                defaults.removeObject(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled)
            }
            for key in cloudRecoveryKeys {
                if let previousValue = previousCloudRecoveryValues[key] {
                    defaults.set(previousValue, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        defaults.set(true, forKey: SyncedPreferenceService.migrationKey)
        let context = try makeTestContext()
        let credentialStore = TestLLMCredentialStore()
        let store = makeTestStore(llmCredentialStore: credentialStore)
        store.configureIfNeeded(context: context)
        let pinnedID = UUID()
        let heatmapTaskIDs = [UUID(), UUID()]

        store.setDefaultFocusMinutes(45)
        store.setDefaultBreakMinutes(12)
        store.setDefaultPomodoroRounds(3)
        store.setAllowParallelTimers(false)
        store.setShowGrossAndWallTogether(false)
        store.setCloudSyncEnabled(false)
        store.setQuickStartTaskIDs([pinnedID])
        store.setTodayHeatmapTaskIDs(heatmapTaskIDs)
        store.setPomodoroPlans([
            PomodoroPlan(
                name: "Writing",
                iconName: "pencil.and.list.clipboard",
                colorHex: "1677FF",
                focusMinutes: 30,
                shortBreakMinutes: 10,
                longBreakMinutes: 20,
                rounds: 5
            )
        ])
        #expect(store.setLLMConfiguration(
            endpoint: " https://example.test/v1 ",
            apiKey: " test-key ",
            selectedModel: " gpt-a ",
            availableModelIDs: ["gpt-z", " gpt-a ", "gpt-a", " "]
        ))
        store.setLLMAutomaticSuggestionsEnabled(true)

        let preferences = store.preferences
        #expect(preferences.defaultFocusMinutes == 45)
        #expect(preferences.defaultBreakMinutes == 12)
        #expect(preferences.defaultPomodoroRounds == 3)
        #expect(preferences.allowParallelTimers == false)
        #expect(preferences.showGrossAndWallTogether == false)
        #expect(preferences.cloudSyncEnabled == false)
        #expect(preferences.quickStartTaskIDs == [pinnedID])
        #expect(preferences.todayHeatmapTaskIDs == heatmapTaskIDs)
        #expect(preferences.pomodoroPlans.count == 1)
        #expect(preferences.pomodoroPlans.first?.name == "Writing")
        #expect(preferences.pomodoroPlans.first?.focusMinutes == 30)
        #expect(preferences.pomodoroPlans.first?.shortBreakMinutes == 10)
        #expect(preferences.pomodoroPlans.first?.longBreakMinutes == 20)
        #expect(preferences.pomodoroPlans.first?.rounds == 5)
        #expect(preferences.llmEndpoint == "https://example.test/v1")
        #expect(preferences.llmAPIKey == "test-key")
        #expect(try credentialStore.readAPIKey() == "test-key")
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).allSatisfy {
            SyncedPreferenceService.shouldSyncKey($0.key)
        })
        #expect(preferences.llmAvailableModelIDs == ["gpt-a", "gpt-z"])
        #expect(preferences.llmSelectedModel == "gpt-a")
        #expect(preferences.llmAutomaticSuggestionsEnabled)
        #expect(defaults.bool(forKey: AppCloudSync.enabledKey) == false)
        #expect(defaults.bool(forKey: AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled))
        #expect(try context.fetch(FetchDescriptor<SyncedPreference>()).contains {
            $0.key == AppLocalPreferenceKey.llmAutomaticSuggestionsEnabled
        } == false)
    }

    @Test @MainActor
    func legacySyncedCloudSettingCannotOverrideThisDevice() throws {
        let defaults = UserDefaults.standard
        let previousMigration = defaults.object(forKey: SyncedPreferenceService.migrationKey)
        let previousCloud = defaults.object(forKey: AppCloudSync.enabledKey)
        defer {
            if let previousMigration {
                defaults.set(previousMigration, forKey: SyncedPreferenceService.migrationKey)
            } else {
                defaults.removeObject(forKey: SyncedPreferenceService.migrationKey)
            }
            if let previousCloud {
                defaults.set(previousCloud, forKey: AppCloudSync.enabledKey)
            } else {
                defaults.removeObject(forKey: AppCloudSync.enabledKey)
            }
        }

        defaults.set(true, forKey: SyncedPreferenceService.migrationKey)
        defaults.set(true, forKey: AppCloudSync.enabledKey)
        let context = try makeTestContext()
        context.insert(
            SyncedPreference(
                key: SyncedPreferenceService.legacyCloudSyncEnabledKey,
                valueJSON: PreferenceJSON.encode(false),
                deviceID: "remote-device"
            )
        )
        try context.save()

        let store = makeTestStore(llmCredentialStore: TestLLMCredentialStore())
        store.configureIfNeeded(context: context)

        #expect(store.preferences.cloudSyncEnabled)
        #expect(defaults.bool(forKey: AppCloudSync.enabledKey))
        #expect(store.syncedPreferences.allSatisfy {
            $0.key != SyncedPreferenceService.legacyCloudSyncEnabledKey
        })
    }

    @Test
    func syncFeedbackExplainsUserVisibleState() {
        let now = Date(timeIntervalSinceReferenceDate: 100_000)
        var preferences = AppPreferences.defaults
        preferences.cloudSyncEnabled = true

        let cloudStatus = SyncStatus(
            mode: "iCloud",
            containerIdentifier: "iCloud.test",
            deviceID: "test",
            lastError: nil,
            accountCheck: CloudAccountCheckOutcome(
                checkedAt: now,
                result: .available
            )
        )
        let recentFeedback = cloudStatus.feedback(
            preferences: preferences,
            isChecking: false,
            activity: SyncActivityOutcome(
                kind: .importData,
                completedAt: now.addingTimeInterval(-45),
                result: .succeeded
            ),
            now: now
        )
        #expect(recentFeedback.state == .recentlySynced)
        #expect(recentFeedback.message.isEmpty == false)

        let checkingFeedback = cloudStatus.feedback(
            preferences: preferences,
            isChecking: true,
            activity: nil,
            now: now
        )
        #expect(checkingFeedback.state == .syncing)

        preferences.cloudSyncEnabled = false
        let restartFeedback = cloudStatus.feedback(
            preferences: preferences,
            isChecking: false,
            activity: nil,
            now: now
        )
        #expect(restartFeedback.state == .needsRestart)

        let failedStatus = SyncStatus(
            mode: "Local fallback",
            containerIdentifier: "iCloud.test",
            deviceID: "test",
            lastError: "CloudKit failed",
            accountCheck: CloudAccountCheckOutcome(
                checkedAt: now,
                result: .available
            )
        )
        preferences.cloudSyncEnabled = true
        let failedFeedback = failedStatus.feedback(
            preferences: preferences,
            isChecking: false,
            activity: nil,
            now: now
        )
        #expect(failedFeedback.state == .failed)
        #expect(failedFeedback.message.contains("CloudKit failed"))

        let temporaryStatus = SyncStatus(
            mode: AppCloudSync.modeInMemoryFallback,
            containerIdentifier: "iCloud.test",
            deviceID: "test",
            lastError: "Store could not open",
            accountCheck: CloudAccountCheckOutcome(
                checkedAt: now,
                result: .available
            )
        )
        let temporaryFeedback = temporaryStatus.feedback(
            preferences: preferences,
            isChecking: false,
            activity: nil,
            now: now
        )
        #expect(temporaryFeedback.state == .temporaryStore)
        #expect(temporaryFeedback.message.contains("Store could not open"))
        #expect(temporaryFeedback.message.contains(AppStrings.localized("sync.storage.temporary")))
    }

    @Test @MainActor
    func checklistDraftsPersistCompletionSortingAndSoftDelete() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Launch", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        var firstDraft = store.editorDraft(for: try #require(store.task(for: task.id)))
        firstDraft.checklistItems = [
            ChecklistEditorDraft(title: "Write copy"),
            ChecklistEditorDraft(title: "Ship build")
        ]
        store.saveTaskDraft(firstDraft)
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Write copy", "Ship build"])

        let existing = store.checklistItems(for: task.id)
        var secondDraft = store.editorDraft(for: try #require(store.task(for: task.id)))
        secondDraft.checklistItems = [
            ChecklistEditorDraft(item: existing[1]),
            ChecklistEditorDraft(item: existing[0])
        ]
        secondDraft.checklistItems[0].isCompleted = true
        secondDraft.checklistItems.removeLast()
        store.saveTaskDraft(secondDraft)

        let activeItems = store.checklistItems(for: task.id)
        let allItems = try context.fetch(FetchDescriptor<ChecklistItem>()).filter { $0.taskID == task.id }
        #expect(activeItems.map(\.title) == ["Ship build"])
        #expect(activeItems.first?.isCompleted == true)
        #expect(activeItems.first?.completedAt != nil)
        #expect(allItems.filter { $0.deletedAt != nil }.count == 1)

        let keptItem = try #require(activeItems.first)
        store.toggleChecklistItem(keptItem)
        #expect(store.checklistItems(for: task.id).first?.isCompleted == false)
        #expect(store.checklistItems(for: task.id).first?.completedAt == nil)
    }

    @Test
    func checklistOrderingRejectsMovesAcrossCompletionBoundary() {
        let service = ChecklistOrderingService()
        let openA = UUID()
        let openB = UUID()
        let doneA = UUID()
        let doneB = UUID()
        let elements = [
            ChecklistOrderingElement(id: openA, isCompleted: false),
            ChecklistOrderingElement(id: openB, isCompleted: false),
            ChecklistOrderingElement(id: doneA, isCompleted: true),
            ChecklistOrderingElement(id: doneB, isCompleted: true)
        ]

        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 1), destination: 0) == [openB, openA, doneA, doneB])
        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 1), destination: 3) == nil)
        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 2), destination: 1) == nil)
        #expect(service.reorderedIDs(elements: elements, sourceOffsets: IndexSet(integer: 2), destination: 4) == [openA, openB, doneB, doneA])
    }

    @Test
    func checklistCompletionGroupingPreservesManualOrderWithinEachState() {
        let service = ChecklistOrderingService()
        let elements = [
            ChecklistOrderingElement(id: "Done A", isCompleted: true),
            ChecklistOrderingElement(id: "Open A", isCompleted: false),
            ChecklistOrderingElement(id: "Done B", isCompleted: true),
            ChecklistOrderingElement(id: "Open B", isCompleted: false)
        ]

        let grouped = service.completionGrouped(
            elements,
            isCompleted: \.isCompleted
        )

        #expect(grouped.map(\.id) == ["Open A", "Open B", "Done A", "Done B"])
    }

    @Test @MainActor
    func checklistCompletionGroupingDoesNotRewriteCanonicalOrderOrSiblingMutations() throws {
        let context = try makeTestContext()
        let task = try SwiftDataTaskRepository(context: context, deviceID: "test")
            .createTask(
                title: "Display grouping",
                parentID: nil,
                colorHex: nil,
                iconName: nil
            )
        let store = makeTestStore()
        store.configureIfNeeded(context: context)
        for title in ["A", "B", "C"] {
            #expect(store.addChecklistItem(taskID: task.id, title: title))
        }

        let before = store.checklistItems(for: task.id)
        let itemA = try #require(before.first { $0.title == "A" })
        let sortOrderByID = Dictionary(uniqueKeysWithValues: before.map {
            ($0.id, $0.sortOrder)
        })
        let siblingMutationIDByID = Dictionary(uniqueKeysWithValues: before
            .filter { $0.id != itemA.id }
            .map { ($0.id, $0.clientMutationID) })

        #expect(store.toggleChecklistItem(itemA))

        let completed = store.checklistItems(for: task.id)
        #expect(completed.map(\.title) == ["A", "B", "C"])
        #expect(Dictionary(uniqueKeysWithValues: completed.map {
            ($0.id, $0.sortOrder)
        }) == sortOrderByID)
        #expect(Dictionary(uniqueKeysWithValues: completed
            .filter { $0.id != itemA.id }
            .map { ($0.id, $0.clientMutationID) }) == siblingMutationIDByID)
        #expect(store.checklistItemsForDisplay(for: task.id).map(\.title) == ["B", "C", "A"])

        let completedA = try #require(completed.first { $0.id == itemA.id })
        #expect(store.toggleChecklistItem(completedA))
        #expect(store.checklistItemsForDisplay(for: task.id).map(\.title) == ["A", "B", "C"])
    }

    @Test @MainActor
    func checklistReorderPersistsWithinCompletionGroups() throws {
        let context = try makeTestContext()
        let taskRepository = SwiftDataTaskRepository(context: context, deviceID: "test")
        let task = try taskRepository.createTask(title: "Checklist Order", parentID: nil, colorHex: nil, iconName: nil)
        let store = makeTestStore()
        store.configureIfNeeded(context: context)

        store.addChecklistItem(taskID: task.id, title: "Open A")
        store.addChecklistItem(taskID: task.id, title: "Open B")
        store.addChecklistItem(taskID: task.id, title: "Done A")
        let doneA = try #require(store.checklistItems(for: task.id).last)
        store.toggleChecklistItem(doneA)

        store.reorderChecklistItems(taskID: task.id, sourceOffsets: IndexSet(integer: 1), destination: 0)
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Open B", "Open A", "Done A"])

        store.reorderChecklistItems(taskID: task.id, sourceOffsets: IndexSet(integer: 1), destination: 3)
        #expect(store.checklistItems(for: task.id).map(\.title) == ["Open B", "Open A", "Done A"])
    }
}

private final class TestLLMCredentialStore: LLMCredentialStoring {
    private var apiKey: String?

    func readAPIKey() throws -> String? {
        apiKey
    }

    func writeAPIKey(_ apiKey: String) throws {
        let normalized = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        self.apiKey = normalized.isEmpty ? nil : normalized
    }
}
