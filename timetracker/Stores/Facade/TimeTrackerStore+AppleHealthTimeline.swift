import Foundation

private enum AppleHealthAuthorizationSheetPolicy {
    case allow
    case avoid
}

extension TimeTrackerStore {
    func showAppleHealthInTimeline(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard appleHealthDataReader.isHealthDataAvailable else {
            appleHealthTimelineState = .unavailable
            return
        }

        appleHealthTimelinePreferenceStore.isTimelineEnabled = true
        isAppleHealthTimelineEnabled = true
        let requestID = beginAppleHealthTimelineRequest()
        materializeAppleHealthTaskCatalog(
            clearRecoveryTaskIDs: appleHealthTimelinePreferenceStore
                .taskCatalogClearRecoveryTaskIDs
        )
        await authorizeAndLoadAppleHealthTimeline(
            requestID: requestID,
            now: now,
            calendar: calendar,
            authorizationSheetPolicy: .allow
        )
    }

    func refreshAppleHealthTimelineIfEnabled(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        // The deterministic task catalog is app navigation metadata, not
        // protected HealthKit sample data. Keep it visible without requesting
        // authorization or requiring the optional Timeline presentation.
        materializeAppleHealthTaskCatalog(
            clearRecoveryTaskIDs: appleHealthTimelinePreferenceStore
                .taskCatalogClearRecoveryTaskIDs
        )
        #if DEBUG
        if applyFirstHealthTimelineFixtureIfRequested(
            now: now,
            calendar: calendar
        ) {
            return
        }
        #endif
        guard isAppleHealthTimelineEnabled else { return }
        await refreshAppleHealthTimeline(
            now: now,
            calendar: calendar,
            authorizationSheetPolicy: .avoid
        )
    }

    func refreshAppleHealthTimeline(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        await refreshAppleHealthTimeline(
            now: now,
            calendar: calendar,
            authorizationSheetPolicy: .allow
        )
    }

    private func refreshAppleHealthTimeline(
        now: Date,
        calendar: Calendar,
        authorizationSheetPolicy: AppleHealthAuthorizationSheetPolicy
    ) async {
        guard appleHealthDataReader.isHealthDataAvailable else {
            appleHealthTimelineItems = []
            appleHealthTimelineState = .unavailable
            return
        }
        guard isAppleHealthTimelineEnabled else {
            appleHealthTimelineItems = []
            appleHealthTimelineState = .disabled
            return
        }

        let requestID = beginAppleHealthTimelineRequest()
        materializeAppleHealthTaskCatalog(
            clearRecoveryTaskIDs: appleHealthTimelinePreferenceStore
                .taskCatalogClearRecoveryTaskIDs
        )
        await authorizeAndLoadAppleHealthTimeline(
            requestID: requestID,
            now: now,
            calendar: calendar,
            authorizationSheetPolicy: authorizationSheetPolicy
        )
    }

    func hideAppleHealthFromTimeline() {
        invalidateAppleHealthTimelineRequest()
        appleHealthTimelinePreferenceStore.isTimelineEnabled = false
        isAppleHealthTimelineEnabled = false
        appleHealthTimelineItems = []
        appleHealthTaskCatalogErrorMessage = nil
        appleHealthTimelineState = appleHealthDataReader.isHealthDataAvailable
            ? .disabled
            : .unavailable
    }

    func timelinePresentationSeed(
        for item: AppleHealthTimelineItem
    ) -> TimelinePresentationSeed {
        let generatedTask = item.taskRole.flatMap {
            task(
                for: AppleHealthTaskCatalog.taskDefinition(for: $0).id
            )
        }
        let category = generatedTask.flatMap {
            effectiveCategory(for: $0)?.title
        } ?? AppStrings.localized(item.categoryLocalizationKey)
        let source = AppStrings.localized("health.timeline.source")
        return TimelinePresentationSeed(
            id: item.id,
            subject: item.subject,
            title: generatedTask?.title ??
                AppStrings.localized(item.titleLocalizationKey),
            path: String(
                format: AppStrings.localized("health.timeline.pathFormat"),
                category,
                source
            ),
            iconName: generatedTask?.iconName ?? item.iconName,
            colorHex: generatedTask?.colorHex ?? item.colorHex,
            interval: item.interval,
            durationIntervals: item.durationIntervals
        )
    }

    private func beginAppleHealthTimelineRequest() -> UUID {
        appleHealthTimelineLoadTask?.cancel()
        appleHealthTimelineLoadTask = nil
        let requestID = UUID()
        appleHealthTimelineRequestID = requestID
        return requestID
    }

    private func invalidateAppleHealthTimelineRequest() {
        appleHealthTimelineLoadTask?.cancel()
        appleHealthTimelineLoadTask = nil
        appleHealthTimelineRequestID = UUID()
    }

    private func isCurrentAppleHealthTimelineRequest(_ requestID: UUID) -> Bool {
        appleHealthTimelineRequestID == requestID
    }

    private func authorizeAndLoadAppleHealthTimeline(
        requestID: UUID,
        now: Date,
        calendar: Calendar,
        authorizationSheetPolicy: AppleHealthAuthorizationSheetPolicy
    ) async {
        do {
            if authorizationSheetPolicy == .avoid {
                let status = try await appleHealthDataReader
                    .authorizationRequestStatus()
                guard isCurrentAppleHealthTimelineRequest(requestID),
                      isAppleHealthTimelineEnabled
                else {
                    return
                }
                switch status {
                case .unnecessary:
                    break
                case .shouldRequest:
                    appleHealthTimelineItems = []
                    appleHealthTimelineState = .ready
                    return
                case .unknown:
                    throw AppleHealthReadError
                        .authorizationRequestStatusUnavailable
                }
            }

            appleHealthTimelineState = .requesting
            try await appleHealthDataReader.requestReadAuthorization()
        } catch is CancellationError {
            guard isCurrentAppleHealthTimelineRequest(requestID),
                  isAppleHealthTimelineEnabled
            else {
                return
            }
            appleHealthTimelineItems = []
            appleHealthTimelineState = .ready
            return
        } catch {
            guard isCurrentAppleHealthTimelineRequest(requestID),
                  isAppleHealthTimelineEnabled
            else {
                return
            }
            appleHealthTimelineItems = []
            appleHealthTimelineState = .failed(error.localizedDescription)
            return
        }

        guard isCurrentAppleHealthTimelineRequest(requestID),
              isAppleHealthTimelineEnabled
        else {
            return
        }
        await loadAppleHealthTimeline(
            requestID: requestID,
            now: now,
            calendar: calendar
        )
    }

    private func loadAppleHealthTimeline(
        requestID: UUID,
        now: Date,
        calendar: Calendar
    ) async {
        let visibleInterval = appleHealthVisibleInterval(
            now: now,
            calendar: calendar
        )
        guard visibleInterval.duration > 0 else {
            guard isCurrentAppleHealthTimelineRequest(requestID) else { return }
            appleHealthTimelineItems = []
            appleHealthTimelineState = .noReadableData(
                interval: visibleInterval,
                refreshedAt: now
            )
            return
        }

        appleHealthTimelineState = .loading(visibleInterval)
        let queryInterval = DateInterval(
            start: visibleInterval.start.addingTimeInterval(
                -AppleHealthSleepEpisodePolicy.queryContextDuration
            ),
            end: visibleInterval.end
        )
        do {
            let loadTask = Task { @MainActor in
                try Task.checkCancellation()
                let batch = try await appleHealthSamples(
                    overlapping: queryInterval
                )
                try Task.checkCancellation()
                return batch
            }
            appleHealthTimelineLoadTask = loadTask
            let batch = try await withTaskCancellationHandler {
                try await loadTask.value
            } onCancel: {
                loadTask.cancel()
            }
            guard isCurrentAppleHealthTimelineRequest(requestID),
                  isAppleHealthTimelineEnabled
            else {
                return
            }
            appleHealthTimelineLoadTask = nil
            let items = AppleHealthTimelineProjectionService().project(
                batch: batch,
                visibleInterval: visibleInterval
            )
            appleHealthTimelineItems = items
            if items.isEmpty {
                appleHealthTimelineState = .noReadableData(
                    interval: visibleInterval,
                    refreshedAt: now
                )
            } else {
                appleHealthTimelineState = .content(
                    interval: visibleInterval,
                    refreshedAt: now,
                    itemCount: items.count
                )
            }
        } catch is CancellationError {
            guard isCurrentAppleHealthTimelineRequest(requestID),
                  isAppleHealthTimelineEnabled
            else {
                return
            }
            appleHealthTimelineLoadTask = nil
            appleHealthTimelineItems = []
            appleHealthTimelineState = .ready
        } catch {
            guard isCurrentAppleHealthTimelineRequest(requestID),
                  isAppleHealthTimelineEnabled
            else {
                return
            }
            appleHealthTimelineLoadTask = nil
            appleHealthTimelineItems = []
            appleHealthTimelineState = .failed(error.localizedDescription)
        }
    }

    func appleHealthSamples(
        overlapping interval: DateInterval
    ) async throws -> AppleHealthSampleBatch {
        guard let appleHealthReplicaSyncService else {
            return try await appleHealthDataReader.samples(
                overlapping: interval
            )
        }
        _ = try await appleHealthReplicaSyncService.synchronize()
        try Task.checkCancellation()
        return try appleHealthReplicaRepository.snapshot(
            overlapping: interval
        ).samples
    }

    private func appleHealthVisibleInterval(
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let day = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(
                start: calendar.startOfDay(for: now),
                duration: 86400
            )
        let end = min(day.end, max(day.start, now))
        return DateInterval(start: day.start, end: end)
    }
}
