import Foundation

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
        appleHealthTimelineState = .requesting
        materializeAppleHealthTaskCatalog(
            clearRecoveryTaskIDs: appleHealthTimelinePreferenceStore
                .taskCatalogClearRecoveryTaskIDs
        )

        do {
            try await appleHealthDataReader.requestReadAuthorization()
        } catch {
            guard isCurrentAppleHealthTimelineRequest(requestID) else { return }
            appleHealthTimelineState = .failed(error.localizedDescription)
            return
        }

        guard isCurrentAppleHealthTimelineRequest(requestID),
              isAppleHealthTimelineEnabled else {
            return
        }
        await loadAppleHealthTimeline(
            requestID: requestID,
            now: now,
            calendar: calendar
        )
    }

    func refreshAppleHealthTimelineIfEnabled(
        now: Date = Date(),
        calendar: Calendar = .current
    ) async {
        guard isAppleHealthTimelineEnabled else { return }
        await refreshAppleHealthTimeline(now: now, calendar: calendar)
    }

    func refreshAppleHealthTimeline(
        now: Date = Date(),
        calendar: Calendar = .current
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
        await loadAppleHealthTimeline(
            requestID: requestID,
            now: now,
            calendar: calendar
        )
    }

    func hideAppleHealthFromTimeline() {
        appleHealthTimelineRequestID = UUID()
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
        let requestID = UUID()
        appleHealthTimelineRequestID = requestID
        return requestID
    }

    private func isCurrentAppleHealthTimelineRequest(_ requestID: UUID) -> Bool {
        appleHealthTimelineRequestID == requestID
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
            let batch = try await appleHealthDataReader.samples(
                overlapping: queryInterval
            )
            guard isCurrentAppleHealthTimelineRequest(requestID),
                  isAppleHealthTimelineEnabled else {
                return
            }
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
        } catch {
            guard isCurrentAppleHealthTimelineRequest(requestID),
                  isAppleHealthTimelineEnabled else {
                return
            }
            appleHealthTimelineItems = []
            appleHealthTimelineState = .failed(error.localizedDescription)
        }
    }

    private func appleHealthVisibleInterval(
        now: Date,
        calendar: Calendar
    ) -> DateInterval {
        let day = calendar.dateInterval(of: .day, for: now)
            ?? DateInterval(
                start: calendar.startOfDay(for: now),
                duration: 86_400
            )
        let end = min(day.end, max(day.start, now))
        return DateInterval(start: day.start, end: end)
    }
}
