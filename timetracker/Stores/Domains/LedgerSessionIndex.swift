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
        arrayIndexByID = Dictionary(uniqueKeysWithValues: sessions.indices.map {
            (sessions[$0].id, $0)
        })
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
                sessions.remove(at: existingIndex)
                arrayIndexByID.removeValue(forKey: id)
                startedAtByID.removeValue(forKey: id)
                taskIDByID.removeValue(forKey: id)
                reindex(from: existingIndex)
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

            sessions.remove(at: existingIndex)
            arrayIndexByID.removeValue(forKey: id)
            startedAtByID.removeValue(forKey: id)
            taskIDByID.removeValue(forKey: id)
            reindex(from: existingIndex)
        }

        guard let session else { return }
        let insertionIndex = insertionIndex(for: session)
        sessions.insert(session, at: insertionIndex)
        startedAtByID[id] = session.startedAt
        taskIDByID[id] = session.taskID
        reindex(from: insertionIndex)
        revision &+= 1
    }

    private mutating func reindex(from startIndex: Int) {
        guard startIndex < sessions.count else { return }
        for index in startIndex ..< sessions.count {
            arrayIndexByID[sessions[index].id] = index
        }
    }

    private func insertionIndex(for session: TimeSession) -> Int {
        var lowerBound = sessions.startIndex
        var upperBound = sessions.endIndex
        while lowerBound < upperBound {
            let middle = lowerBound + sessions.distance(from: lowerBound, to: upperBound) / 2
            if sessionOrder(sessions[middle], session) {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func sessionOrder(_ lhs: TimeSession, _ rhs: TimeSession) -> Bool {
        if lhs.startedAt != rhs.startedAt {
            return lhs.startedAt > rhs.startedAt
        }
        return lhs.id < rhs.id
    }
}
