import Foundation
import SwiftData

protocol TaskRepository {
    func allNodes() throws -> [TaskNode]
    func rootNodes() throws -> [TaskNode]
    func children(of parentID: UUID?) throws -> [TaskNode]
    func task(id: UUID) throws -> TaskNode?
    @discardableResult func createTask(title: String, kind: TaskNodeKind, parentID: UUID?, colorHex: String?, iconName: String?) throws -> TaskNode
    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws
    func archiveTask(taskID: UUID) throws
    func softDeleteTask(taskID: UUID) throws
}

protocol TimeTrackingRepository {
    func activeSegments() throws -> [TimeSegment]
    func sessions() throws -> [TimeSession]
    func segments(from: Date, to: Date) throws -> [TimeSegment]
    @discardableResult func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment
    func stopSegment(segmentID: UUID) throws
    func pauseSession(sessionID: UUID) throws
    @discardableResult func resumeSession(sessionID: UUID) throws -> TimeSegment?
    @discardableResult func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment
}

protocol PomodoroRepository {
    @discardableResult func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, targetRounds: Int) throws -> PomodoroRun
    func completeFocus(runID: UUID) throws
}

@MainActor
final class SwiftDataTaskRepository: TaskRepository {
    private let context: ModelContext
    private let deviceID: String

    init(context: ModelContext, deviceID: String? = nil) {
        self.context = context
        self.deviceID = deviceID ?? DeviceIdentity.current
    }

    func allNodes() throws -> [TaskNode] {
        let descriptor = FetchDescriptor<TaskNode>(
            sortBy: [
                SortDescriptor(\.depth),
                SortDescriptor(\.sortOrder),
                SortDescriptor(\.createdAt)
            ]
        )
        return try context.fetch(descriptor).filter { $0.deletedAt == nil }
    }

    func rootNodes() throws -> [TaskNode] {
        try children(of: nil)
    }

    func children(of parentID: UUID?) throws -> [TaskNode] {
        try allNodes()
            .filter { $0.parentID == parentID }
            .sorted { lhs, rhs in
                if lhs.sortOrder == rhs.sortOrder {
                    return lhs.createdAt < rhs.createdAt
                }
                return lhs.sortOrder < rhs.sortOrder
            }
    }

    func task(id: UUID) throws -> TaskNode? {
        try allNodes().first { $0.id == id }
    }

    @discardableResult
    func createTask(title: String, kind: TaskNodeKind, parentID: UUID?, colorHex: String? = nil, iconName: String? = nil) throws -> TaskNode {
        let siblings = try children(of: parentID)
        let node = TaskNode(
            title: title,
            kind: kind,
            parentID: parentID,
            deviceID: deviceID,
            colorHex: colorHex,
            iconName: iconName,
            sortOrder: (siblings.last?.sortOrder ?? 0) + 10
        )

        try applyHierarchy(to: node, parentID: parentID)
        context.insert(node)
        try context.save()
        return node
    }

    func moveTask(taskID: UUID, newParentID: UUID?, sortOrder: Double) throws {
        let nodes = try allNodes()
        guard let node = nodes.first(where: { $0.id == taskID }) else { return }
        guard canMove(nodeID: taskID, to: newParentID, nodes: nodes) else { return }

        node.parentID = newParentID
        node.sortOrder = sortOrder
        node.updatedAt = Date()
        node.clientMutationID = UUID()
        try applyHierarchy(to: node, parentID: newParentID)
        try updateDescendantHierarchy(of: node)
        try context.save()
    }

    func archiveTask(taskID: UUID) throws {
        guard let node = try task(id: taskID) else { return }
        node.status = .archived
        node.archivedAt = Date()
        node.updatedAt = Date()
        node.clientMutationID = UUID()
        try context.save()
    }

    func softDeleteTask(taskID: UUID) throws {
        guard let node = try task(id: taskID) else { return }
        node.deletedAt = Date()
        node.updatedAt = Date()
        node.clientMutationID = UUID()
        try context.save()
    }

    private func canMove(nodeID: UUID, to newParentID: UUID?, nodes: [TaskNode]) -> Bool {
        guard let newParentID else { return true }
        guard nodeID != newParentID else { return false }
        return !descendantIDs(of: nodeID, nodes: nodes).contains(newParentID)
    }

    private func descendantIDs(of nodeID: UUID, nodes: [TaskNode]) -> Set<UUID> {
        let directChildren = nodes.filter { $0.parentID == nodeID }
        return directChildren.reduce(into: Set<UUID>()) { result, child in
            result.insert(child.id)
            result.formUnion(descendantIDs(of: child.id, nodes: nodes))
        }
    }

    private func applyHierarchy(to node: TaskNode, parentID: UUID?) throws {
        if let parentID, let parent = try task(id: parentID) {
            node.depth = parent.depth + 1
            node.path = parent.path + "/" + node.id.uuidString
        } else {
            node.depth = 0
            node.path = "/" + node.id.uuidString
        }
    }

    private func updateDescendantHierarchy(of node: TaskNode) throws {
        let children = try children(of: node.id)
        for child in children {
            child.depth = node.depth + 1
            child.path = node.path + "/" + child.id.uuidString
            child.updatedAt = Date()
            try updateDescendantHierarchy(of: child)
        }
    }
}

@MainActor
final class SwiftDataTimeTrackingRepository: TimeTrackingRepository {
    private let context: ModelContext
    private let deviceID: String

    init(context: ModelContext, deviceID: String? = nil) {
        self.context = context
        self.deviceID = deviceID ?? DeviceIdentity.current
    }

    func activeSegments() throws -> [TimeSegment] {
        let descriptor = FetchDescriptor<TimeSegment>(sortBy: [SortDescriptor(\.startedAt)])
        return try context.fetch(descriptor).filter { $0.endedAt == nil && $0.deletedAt == nil }
    }

    func sessions() throws -> [TimeSession] {
        let descriptor = FetchDescriptor<TimeSession>(sortBy: [SortDescriptor(\.startedAt, order: .reverse)])
        return try context.fetch(descriptor).filter { $0.deletedAt == nil }
    }

    func segments(from: Date, to: Date) throws -> [TimeSegment] {
        let descriptor = FetchDescriptor<TimeSegment>(sortBy: [SortDescriptor(\.startedAt)])
        return try context.fetch(descriptor).filter { segment in
            guard segment.deletedAt == nil else { return false }
            let end = segment.endedAt ?? Date()
            return segment.startedAt < to && end > from
        }
    }

    @discardableResult
    func startTask(taskID: UUID, source: TimeSessionSource) throws -> TimeSegment {
        let session = TimeSession(taskID: taskID, source: source, deviceID: deviceID)
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: source, deviceID: deviceID)
        context.insert(session)
        context.insert(segment)
        try context.save()
        return segment
    }

    func stopSegment(segmentID: UUID) throws {
        guard let segment = try segment(id: segmentID), segment.endedAt == nil else { return }
        let now = Date()
        segment.endedAt = now
        segment.updatedAt = now

        if let session = try session(id: segment.sessionID),
           try activeSegments().contains(where: { $0.sessionID == session.id }) == false {
            session.endedAt = now
            session.updatedAt = now
        }

        try context.save()
    }

    func pauseSession(sessionID: UUID) throws {
        let now = Date()
        for segment in try activeSegments().filter({ $0.sessionID == sessionID }) {
            segment.endedAt = now
            segment.updatedAt = now
        }
        try context.save()
    }

    @discardableResult
    func resumeSession(sessionID: UUID) throws -> TimeSegment? {
        guard let session = try session(id: sessionID), session.deletedAt == nil else { return nil }
        let segment = TimeSegment(sessionID: session.id, taskID: session.taskID, source: TimeSessionSource(rawValue: session.sourceRaw) ?? .timer, deviceID: deviceID)
        session.endedAt = nil
        session.updatedAt = Date()
        context.insert(segment)
        try context.save()
        return segment
    }

    @discardableResult
    func addManualSegment(taskID: UUID, startedAt: Date, endedAt: Date, note: String?) throws -> TimeSegment {
        let session = TimeSession(taskID: taskID, source: .manual, deviceID: deviceID, startedAt: startedAt)
        session.endedAt = endedAt
        session.note = note
        let segment = TimeSegment(sessionID: session.id, taskID: taskID, source: .manual, deviceID: deviceID, startedAt: startedAt, endedAt: endedAt)
        context.insert(session)
        context.insert(segment)
        try context.save()
        return segment
    }

    private func segment(id: UUID) throws -> TimeSegment? {
        let descriptor = FetchDescriptor<TimeSegment>()
        return try context.fetch(descriptor).first { $0.id == id && $0.deletedAt == nil }
    }

    private func session(id: UUID) throws -> TimeSession? {
        let descriptor = FetchDescriptor<TimeSession>()
        return try context.fetch(descriptor).first { $0.id == id && $0.deletedAt == nil }
    }
}

@MainActor
final class SwiftDataPomodoroRepository: PomodoroRepository {
    private let context: ModelContext
    private let timeRepository: TimeTrackingRepository
    private let deviceID: String

    init(context: ModelContext, timeRepository: TimeTrackingRepository, deviceID: String? = nil) {
        self.context = context
        self.timeRepository = timeRepository
        self.deviceID = deviceID ?? DeviceIdentity.current
    }

    @discardableResult
    func startPomodoro(taskID: UUID, focusSeconds: Int, breakSeconds: Int, targetRounds: Int) throws -> PomodoroRun {
        let run = PomodoroRun(taskID: taskID, focus: focusSeconds, breakSeconds: breakSeconds, targetRounds: targetRounds, deviceID: deviceID)
        let segment = try timeRepository.startTask(taskID: taskID, source: .pomodoro)
        run.sessionID = segment.sessionID
        run.startedAt = Date()
        run.state = .focusing
        run.updatedAt = Date()
        context.insert(run)
        try context.save()
        return run
    }

    func completeFocus(runID: UUID) throws {
        let descriptor = FetchDescriptor<PomodoroRun>()
        guard let run = try context.fetch(descriptor).first(where: { $0.id == runID && $0.deletedAt == nil }) else { return }
        if let sessionID = run.sessionID {
            try timeRepository.pauseSession(sessionID: sessionID)
        }
        run.completedFocusRounds += 1
        run.state = run.completedFocusRounds >= run.targetRounds ? .completed : .shortBreak
        run.endedAt = run.state == .completed ? Date() : nil
        run.updatedAt = Date()
        try context.save()
    }
}
