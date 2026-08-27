import Foundation
import Observation

/// Shared bounded-concurrency request lifecycle for LLM suggestion features.
/// Holds in-flight request identity, an optional per-item debounce stage, a
/// pending FIFO queue, and the per-item failure payload. Feature-specific
/// result handling stays in the owning store through the completion closures
/// passed to `start`.
@MainActor
@Observable
final class LLMSuggestionRequestLifecycle<ItemID: Hashable, Failure> {
    let maximumConcurrency: Int

    private(set) var inFlightIDs: Set<ItemID> = []
    @ObservationIgnored private(set) var tasksByItemID: [ItemID: StoreLLMSuggestionTask] = [:]
    var failureByItemID: [ItemID: Failure] = [:]
    @ObservationIgnored private(set) var pendingIDs: [ItemID] = []
    @ObservationIgnored private(set) var pendingShowsErrors: Set<ItemID> = []
    @ObservationIgnored private(set) var debounceTasksByItemID: [ItemID: StoreLLMSuggestionDebounceTask] = [:]

    init(maximumConcurrency: Int) {
        self.maximumConcurrency = maximumConcurrency
    }

    deinit {
        for request in tasksByItemID.values {
            request.task.cancel()
        }
        for request in debounceTasksByItemID.values {
            request.task.cancel()
        }
    }

    var availableSlots: Int {
        max(0, maximumConcurrency - inFlightIDs.count)
    }

    /// Slots left after also reserving capacity for debouncing items, used by
    /// features whose debounce stage occupies a concurrency slot.
    var debouncedAvailableSlots: Int {
        max(0, maximumConcurrency - inFlightIDs.count - debounceTasksByItemID.count)
    }

    func isCurrentRequest(itemID: ItemID, requestID: UUID) -> Bool {
        tasksByItemID[itemID]?.requestID == requestID
    }

    func requestSnapshot() -> [ItemID: UUID] {
        tasksByItemID.mapValues(\.requestID)
    }

    // MARK: Pending queue

    func enqueue(itemID: ItemID, showsErrors: Bool) {
        if pendingIDs.contains(itemID) == false {
            pendingIDs.append(itemID)
        }
        if showsErrors {
            pendingShowsErrors.insert(itemID)
        }
    }

    func dequeuePending() -> (itemID: ItemID, showsErrors: Bool)? {
        guard pendingIDs.isEmpty == false else { return nil }
        let itemID = pendingIDs.removeFirst()
        return (itemID, pendingShowsErrors.remove(itemID) != nil)
    }

    func removePending(itemID: ItemID) {
        pendingIDs.removeAll { $0 == itemID }
        pendingShowsErrors.remove(itemID)
    }

    func removePending(for itemIDs: Set<ItemID>) {
        pendingIDs.removeAll { itemIDs.contains($0) }
        pendingShowsErrors.subtract(itemIDs)
    }

    func removeAutomaticPending() {
        pendingIDs.removeAll { pendingShowsErrors.contains($0) == false }
    }

    func clearPending() {
        pendingIDs.removeAll(keepingCapacity: true)
        pendingShowsErrors.removeAll(keepingCapacity: true)
    }

    // MARK: In-flight requests

    /// Starts the request task, claiming an in-flight slot for the item.
    /// `perform` runs even if the owning store is released; the completion
    /// closures decide whether the result still applies.
    @discardableResult
    func start<Success>(
        itemID: ItemID,
        isAutomatic: Bool,
        perform: @escaping () async throws -> Success,
        onSuccess: @escaping @MainActor (Success, UUID) -> Void,
        onFailure: @escaping @MainActor (Error, UUID, Bool) -> Void
    ) -> UUID {
        let requestID = UUID()
        inFlightIDs.insert(itemID)
        let task = Task { @MainActor in
            do {
                let result = try await perform()
                try Task.checkCancellation()
                onSuccess(result, requestID)
            } catch {
                onFailure(
                    error,
                    requestID,
                    Task.isCancelled || error is CancellationError
                )
            }
        }
        tasksByItemID[itemID] = StoreLLMSuggestionTask(
            requestID: requestID,
            isAutomatic: isAutomatic,
            task: task
        )
        return requestID
    }

    /// Removes the request bookkeeping for a current request. Returns false
    /// when the request ID is stale and nothing was touched.
    @discardableResult
    func finish(itemID: ItemID, requestID: UUID) -> Bool {
        guard isCurrentRequest(itemID: itemID, requestID: requestID) else { return false }
        tasksByItemID.removeValue(forKey: itemID)
        inFlightIDs.remove(itemID)
        return true
    }

    func cancelInFlight(where shouldCancel: (ItemID, StoreLLMSuggestionTask) -> Bool) {
        let requests = tasksByItemID.filter { shouldCancel($0.key, $0.value) }
        for (itemID, request) in requests {
            guard tasksByItemID[itemID]?.requestID == request.requestID else { continue }
            tasksByItemID.removeValue(forKey: itemID)
            inFlightIDs.remove(itemID)
            request.task.cancel()
        }
    }

    func cancelInFlight(for itemIDs: Set<ItemID>, onCancel: (ItemID) -> Void = { _ in }) {
        guard itemIDs.isEmpty == false else { return }
        for itemID in itemIDs {
            guard let request = tasksByItemID[itemID] else { continue }
            tasksByItemID.removeValue(forKey: itemID)
            inFlightIDs.remove(itemID)
            onCancel(itemID)
            request.task.cancel()
        }
    }

    func cancelInFlight(matching requestIDsByItemID: [ItemID: UUID]) {
        guard requestIDsByItemID.isEmpty == false else { return }
        cancelInFlight { itemID, request in
            requestIDsByItemID[itemID] == request.requestID
        }
    }

    // MARK: Debounce

    func scheduleDebounce(
        itemID: ItemID,
        fingerprint: String,
        delay: Duration,
        fire: @escaping @MainActor (ItemID, String) -> Void
    ) {
        let task = Task { @MainActor in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            fire(itemID, fingerprint)
        }
        debounceTasksByItemID[itemID] = StoreLLMSuggestionDebounceTask(
            schedulingFingerprint: fingerprint,
            task: task
        )
    }

    /// Consumes the debounce entry when its fingerprint is still current.
    /// Returns false when a newer schedule superseded it.
    @discardableResult
    func finishDebounce(itemID: ItemID, fingerprint: String) -> Bool {
        guard debounceTasksByItemID[itemID]?.schedulingFingerprint == fingerprint
        else { return false }
        debounceTasksByItemID.removeValue(forKey: itemID)
        return true
    }

    func cancelDebounce(for itemIDs: Set<ItemID>) {
        guard itemIDs.isEmpty == false else { return }
        for itemID in itemIDs {
            guard let request = debounceTasksByItemID.removeValue(forKey: itemID)
            else { continue }
            request.task.cancel()
        }
    }
}
