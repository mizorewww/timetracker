import Foundation

extension TimeTrackerStore {
    func loadTaskAnalyticsSnapshot(
        for request: TaskAnalyticsSnapshotRequest,
        now: Date = Date(),
        calendar: Calendar = .current,
        allowsAuthorizationRequest: Bool
    ) async throws -> TaskAnalyticsSnapshot? {
        try Task.checkCancellation()
        guard let task = task(for: request.taskID) else { return nil }
        guard let role = AppleHealthTaskCatalog.taskRole(
            for: request.taskID
        ) else {
            return taskAnalyticsSnapshot(
                for: request,
                now: now,
                calendar: calendar
            )
        }
        guard appleHealthDataReader.isHealthDataAvailable else {
            throw AppleHealthReadError.unavailable
        }

        let projectionService = AppleHealthTaskAnalyticsProjectionService()
        let taskTitle = task.title
        let taskPath = taskPathByID[task.id] ?? task.title

        if allowsAuthorizationRequest {
            try await appleHealthDataReader.requestReadAuthorization()
            try Task.checkCancellation()
        } else {
            let authorizationStatus = try await appleHealthDataReader
                .authorizationRequestStatus()
            try Task.checkCancellation()
            switch authorizationStatus {
            case .unnecessary:
                break
            case .shouldRequest:
                return projectionService.snapshot(
                    role: role,
                    taskID: task.id,
                    title: taskTitle,
                    path: taskPath,
                    batch: .empty,
                    request: request,
                    now: now,
                    calendar: calendar
                )
            case .unknown:
                throw AppleHealthReadError
                    .authorizationRequestStatusUnavailable
            }
        }

        let queryPlan = projectionService.queryPlan(
            for: request,
            now: now,
            calendar: calendar
        )
        let batch = try await appleHealthSamples(
            overlapping: queryPlan.queryInterval
        )
        try Task.checkCancellation()
        return projectionService.snapshot(
            role: role,
            taskID: task.id,
            title: taskTitle,
            path: taskPath,
            batch: batch,
            request: request,
            now: now,
            calendar: calendar
        )
    }
}
