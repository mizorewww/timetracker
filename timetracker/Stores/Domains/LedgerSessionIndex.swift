import Foundation

/// Maintains the session read model without filtering, deduplicating, and
/// sorting the complete session history after a segment-sized mutation.
struct LedgerSessionIndex {
    private(set) var sessions: [TimeSession] = []
    /// Advances whenever membership, order, or a session's task changes.
    private(set) var revision: UInt64 = 0

    private var arrayIndexByID: [UUID: Int] = [:]
    private var startedAtByID: [UUID: Date] = [:]
    private var taskIDByID: [UUID: UUID] = [:]

    mutating func rebuild(_ fetchedSessions: [TimeSession]) {
        sessions = fetchedSessions.visibleDeduplicatedByID().sorted(by: sessionOrder)
        arrayIndexByID = SortedUUIDArrayIndex.buildIndex(for: sessions)
        startedAtByID = Dictionary(uniqueKeysWithValues: sessions.map {
            ($0.id, $0.startedAt)
        })
        taskIDByID = Dictionary(uniqueKeysWithValues: sessions.map {
            ($0.id, $0.taskID)
        })
        revision &+= 1
    }

    /// Returns the IDs whose membership, order, model, or task changed.
    @discardableResult
    mutating func replace(ids: Set<UUID>, with fetchedSessions: [TimeSession]) -> Set<UUID> {
        let fetchedByID = fetchedSessions.visibleDeduplicatedByID().reduce(
            into: [UUID: TimeSession]()
        ) { result, session in
            result[session.id] = session
        }
        var changedIDs = Set<UUID>()
        for id in ids {
            let previousRevision = revision
            update(
                id: id,
                previousStartedAt: startedAtByID[id],
                session: fetchedByID[id]
            )
            if revision != previousRevision {
                changedIDs.insert(id)
            }
        }
        return changedIDs
    }

    func session(for id: UUID) -> TimeSession? {
        guard let index = arrayIndexByID[id] else { return nil }
        return sessions[index]
    }

    func sessions(for ids: Set<UUID>) -> [TimeSession] {
        ids.compactMap { id in
            guard let index = arrayIndexByID[id] else { return nil }
            return sessions[index]
        }
    }

    private mutating func update(
        id: UUID,
        previousStartedAt: Date?,
        session: TimeSession?
    ) {
        if let existingIndex = arrayIndexByID[id] {
            guard let session else {
                SortedUUIDArrayIndex.remove(
                    ids: [id],
                    from: &sessions,
                    indexByID: &arrayIndexByID
                )
                startedAtByID.removeValue(forKey: id)
                taskIDByID.removeValue(forKey: id)
                revision &+= 1
                return
            }

            if previousStartedAt == session.startedAt {
                if sessions[existingIndex] !== session || taskIDByID[id] != session.taskID {
                    sessions[existingIndex] = session
                    taskIDByID[id] = session.taskID
                    revision &+= 1
                }
                return
            }

            SortedUUIDArrayIndex.remove(
                ids: [id],
                from: &sessions,
                indexByID: &arrayIndexByID
            )
            startedAtByID.removeValue(forKey: id)
            taskIDByID.removeValue(forKey: id)
        }

        guard let session else { return }
        SortedUUIDArrayIndex.insert(
            [session],
            into: &sessions,
            indexByID: &arrayIndexByID,
            orderedBy: sessionOrder
        )
        startedAtByID[id] = session.startedAt
        taskIDByID[id] = session.taskID
        revision &+= 1
    }

    private func sessionOrder(_ lhs: TimeSession, _ rhs: TimeSession) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.id < rhs.id
    }
}
