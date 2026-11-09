import Foundation

/// The coding agents whose local hooks can drive the tube. All agents share
/// one combined status; the agent only selects how an event is interpreted.
public enum AgentKind: String, Codable, CaseIterable, Sendable { case codex, claude }

public enum AgentActivity: String, Sendable { case unknown, idle, working, waiting, failed, finished }
public enum AgentStatusCue: String, Sendable { case stopped, interrupted }

public struct AgentStatusSnapshot: Equatable, Sendable {
    public var activity: AgentActivity
    public var cue: AgentStatusCue?
    public var cueID: String?
    public var cueDate: Date?
    public var activeCount: Int

    public init(activity: AgentActivity = .unknown, cue: AgentStatusCue? = nil,
                cueID: String? = nil, cueDate: Date? = nil, activeCount: Int = 0) {
        self.activity = activity; self.cue = cue; self.cueID = cueID
        self.cueDate = cueDate; self.activeCount = activeCount
    }

    public var accessibilityDescription: String {
        switch activity {
        case .unknown: return "Agent status unavailable"
        case .working: return "Agent is working"
        case .waiting: return "Agent needs a decision or approval"
        case .failed: return "Agent turn failed"
        case .finished: return "Agent turn finished. Click the tube to open the session."
        case .idle:
            switch cue {
            case .stopped: return "Observed agent turn ended"
            case .interrupted: return "Agent turn interrupted"
            case nil: return "Observed agent chats are idle"
            }
        }
    }
}

/// Allow-listed metadata received from a local hook, never chat content.
public struct AgentEvent: Codable, Equatable, Sendable {
    public let schema: Int
    public let agent: AgentKind
    public let eventID: String
    public let sessionID: String
    public let turnID: String?
    public let event: String
    public let time: Double
    public let status: String?
    /// Owning agent process. A session whose owner exits can never finish.
    public let pid: Int32?
    /// Preview length in seconds; only meaningful for `Preview`.
    public let duration: Double?
    /// Usage-limit percent and reset time; only meaningful for `Usage`.
    public let usedPercent: Double?
    public let resetsAt: Double?

    public static let previewStates = ["working", "waiting", "failed", "finished", "clear"]

    private enum CodingKeys: String, CodingKey {
        case schema, agent, eventID, sessionID, turnID, event, time, status, pid, duration, usedPercent, resetsAt
    }

    public init(schema: Int = 2, agent: AgentKind = .codex, eventID: String = UUID().uuidString,
                sessionID: String, turnID: String? = nil, event: String,
                time: Double = Date().timeIntervalSince1970, status: String? = nil,
                pid: Int32? = nil, duration: Double? = nil, usedPercent: Double? = nil, resetsAt: Double? = nil) {
        self.schema = schema; self.agent = agent; self.eventID = eventID; self.sessionID = sessionID
        self.turnID = turnID; self.event = event; self.time = time; self.status = status
        self.pid = pid; self.duration = duration; self.usedPercent = usedPercent; self.resetsAt = resetsAt
    }

    /// A usage reading from an agent, carried on the same local socket.
    public static func usage(_ usage: AgentUsage, now: Date = Date()) -> AgentEvent {
        AgentEvent(agent: usage.agent, sessionID: "usage", event: "Usage", time: now.timeIntervalSince1970,
                   usedPercent: usage.usedPercent, resetsAt: usage.resetsAt?.timeIntervalSince1970)
    }

    public var usageReading: AgentUsage? {
        guard event == "Usage", let usedPercent else { return nil }
        return AgentUsage(agent: agent, usedPercent: usedPercent,
                          resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)),
                          observedAt: Date(timeIntervalSince1970: time))
    }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schema = try values.decode(Int.self, forKey: .schema)
        // Schema 1 datagrams come from older installed Codex hooks.
        agent = try values.decodeIfPresent(AgentKind.self, forKey: .agent) ?? .codex
        eventID = try values.decode(String.self, forKey: .eventID)
        sessionID = try values.decode(String.self, forKey: .sessionID)
        turnID = try values.decodeIfPresent(String.self, forKey: .turnID)
        event = try values.decode(String.self, forKey: .event)
        time = try values.decode(Double.self, forKey: .time)
        status = try values.decodeIfPresent(String.self, forKey: .status)
        pid = try values.decodeIfPresent(Int32.self, forKey: .pid)
        duration = try values.decodeIfPresent(Double.self, forKey: .duration)
        usedPercent = try values.decodeIfPresent(Double.self, forKey: .usedPercent)
        resetsAt = try values.decodeIfPresent(Double.self, forKey: .resetsAt)
    }

    var sessionKey: String { agent.rawValue + ":" + sessionID }

    public func isValid(at now: Date) -> Bool {
        let allowed = ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "Interrupt",
                       "SessionEnd", "PermissionRequest", "PreModelRequest", "DecisionRequest",
                       "DecisionRequestAsync", "TurnStarted", "TurnCompleted", "ThreadStatus",
                       "StopFailure", "IdlePrompt", "Preview", "Usage", "ThreadUnavailable"]
        let statuses = ["completed", "failed", "interrupted", "working", "waiting", "idle", "unknown"]
        guard (schema == 1 || schema == 2), !eventID.isEmpty, eventID.utf8.count <= 128,
              !sessionID.isEmpty, sessionID.utf8.count <= 256,
              (turnID?.utf8.count ?? 0) <= 256, allowed.contains(event),
              (pid ?? 1) > 0, time.isFinite, abs(now.timeIntervalSince1970 - time) <= 30 else { return false }
        if event == "Usage" {
            guard let usedPercent, usedPercent.isFinite, usedPercent >= 0, usedPercent <= 1000 else { return false }
            return resetsAt.map(\.isFinite) ?? true
        }
        if event == "Preview" {
            guard let status, Self.previewStates.contains(status) else { return false }
            if status == "clear" { return true }
            guard let duration, duration.isFinite, duration > 0, duration <= 60 else { return false }
            return true
        }
        return status == nil || statuses.contains(status!)
    }
}

/// One agent session the user can be taken to.
public struct AgentSessionRef: Equatable, Sendable {
    public let agent: AgentKind
    public let sessionID: String
    public let pid: Int32?
    public let activity: AgentActivity

    public var key: String { agent.rawValue + ":" + sessionID }
}

/// Activity stays latched until a definite replacement state arrives.
///
/// Codex: a generic Stop or SessionEnd can precede the stored outcome, so
/// neither clears color; `TurnCompleted` from the metadata monitor decides.
/// Claude Code: Stop is the turn-completion signal, StopFailure a failed turn,
/// and an idle prompt proves an interrupted turn has ended.
public struct AgentStatusReducer: Sendable {
    private struct Session: Sendable {
        var agent: AgentKind
        var sessionID: String
        var turn: String?
        var time: Double
        var activity: AgentActivity
        var decisionPending = false
        var pid: Int32?
        /// Codex sent Stop or SessionEnd for the current turn.
        var stopped = false
    }
    public private(set) var snapshot = AgentStatusSnapshot()
    private var sessions: [String: Session] = [:]
    private var seen: Set<String> = []

    public init() {}

    public func isTracking(agent: AgentKind = .codex, session: String, turn: String) -> Bool {
        sessions[agent.rawValue + ":" + session]?.turn == turn
    }

    /// Codex turns still awaiting a stored outcome, whichever event supplied the turn ID.
    public func activeCodexTurns() -> [String: String] {
        var result: [String: String] = [:]
        for session in sessions.values where session.agent == .codex
            && (session.activity == .working || session.activity == .waiting) {
            if let turn = session.turn { result[session.sessionID] = turn }
        }
        return result
    }

    public var hasActiveOwnedSessions: Bool {
        sessions.values.contains { $0.pid != nil && ($0.activity == .working || $0.activity == .waiting) }
    }

    /// Removes active sessions whose owning agent process has exited. This is
    /// evidence that the turn can never report an outcome, not a timeout.
    @discardableResult
    public mutating func pruneDeadOwners(isAlive: (Int32) -> Bool, at now: Date = Date()) -> Bool {
        let dead = sessions.filter { _, session in
            guard let pid = session.pid else { return false }
            return (session.activity == .working || session.activity == .waiting) && !isAlive(pid)
        }.map(\.key)
        guard !dead.isEmpty else { return false }
        for key in dead { sessions.removeValue(forKey: key) }
        refresh(at: now)
        return true
    }

    /// Drops one agent's sessions when it is disconnected; other agents keep
    /// their status.
    public mutating func forget(agent: AgentKind, at now: Date = Date()) {
        sessions = sessions.filter { $0.value.agent != agent }
        refresh(at: now)
    }

    public mutating func disconnect() {
        sessions = [:]; seen = []; snapshot = AgentStatusSnapshot()
    }

    public mutating func receive(_ event: AgentEvent, at now: Date = Date()) {
        guard event.isValid(at: now), event.event != "Preview", event.event != "Usage",
              !seen.contains(event.eventID) else { return }
        let key = event.sessionKey
        let claude = event.agent == .claude
        if event.event == "TurnCompleted" {
            guard let turn = event.turnID, isTracking(agent: event.agent, session: event.sessionID, turn: turn) else { return }
            // A second app-server reading a turn still being written reports
            // it as interrupted. Only trust that once Codex has said Stop;
            // a real Esc arrives as an Interrupt hook.
            if event.status == "interrupted", sessions[key]?.stopped != true { return }
        }
        // Codex never stores its hidden helper threads (titles, suggestions,
        // memory), so no outcome can ever be read for them. Once Codex has
        // said Stop, "not loaded" proves the thread is one of those.
        if event.event == "ThreadUnavailable" {
            guard !claude, let session = sessions[key], session.stopped,
                  session.activity == .working || session.activity == .waiting,
                  event.turnID == nil || event.turnID == session.turn else { return }
            sessions.removeValue(forKey: key)
            refresh(at: now)
            return
        }
        // Resume/compaction can emit SessionStart during an existing turn.
        // It carries no activity evidence and must not erase a known state.
        if event.event == "SessionStart", sessions[key] != nil { return }
        if let prior = sessions[key] {
            guard event.time >= prior.time else { return }
            // Codex hooks can trail the stored outcome of the same turn. Claude
            // Code has no turn IDs; its newer tool events reopen work.
            if !claude, (prior.activity == .finished || prior.activity == .failed), prior.turn == event.turnID,
               ["PreToolUse", "PostToolUse", "PreModelRequest", "PermissionRequest", "DecisionRequest", "DecisionRequestAsync"].contains(event.event) {
                return
            }
            if !["UserPromptSubmit", "SessionStart", "TurnStarted"].contains(event.event),
               let turn = event.turnID, let previousTurn = prior.turn, turn != previousTurn { return }
        }
        seen.insert(event.eventID)
        if seen.count > 1024 { seen = [event.eventID] }
        // A new prompt clears only its own session's result (it becomes
        // working below); other sessions keep green/red until opened.
        let priorActivity = sessions[key]?.activity
        var activity: AgentActivity = .unknown
        switch event.event {
        case "UserPromptSubmit", "PreToolUse", "PostToolUse", "PreModelRequest", "TurnStarted": activity = .working
        case "PermissionRequest", "DecisionRequest", "DecisionRequestAsync": activity = .waiting
        case "ThreadStatus":
            switch event.status {
            case "working": activity = .working
            case "waiting": activity = .waiting
            case "idle": activity = priorActivity ?? .idle
            case "failed": activity = .failed
            default: activity = .unknown
            }
        case "TurnCompleted":
            switch event.status {
            case "completed": activity = .finished
            case "failed": activity = .failed
            case "interrupted": activity = .idle
            default: return
            }
        case "Stop":
            activity = claude ? .finished : priorActivity ?? .unknown
        case "StopFailure": activity = .failed
        case "IdlePrompt":
            // Waiting for input proves an interrupted turn ended; it must not
            // erase an unacknowledged outcome.
            if let priorActivity, [.finished, .failed, .idle].contains(priorActivity) { activity = priorActivity }
            else { activity = .idle }
        case "Interrupt": activity = .idle
        case "SessionEnd":
            if let priorActivity, (claude ? [.finished, .failed] : [.working, .waiting, .finished, .failed]).contains(priorActivity) {
                activity = priorActivity
            } else { sessions.removeValue(forKey: key) }
        default: break
        }
        if event.event != "SessionEnd" || [.working, .waiting, .finished, .failed].contains(activity) {
            var pending = event.event == "DecisionRequestAsync" || sessions[key]?.decisionPending == true
            if ["UserPromptSubmit", "TurnStarted", "TurnCompleted", "Interrupt", "Stop", "StopFailure", "IdlePrompt"].contains(event.event),
               claude || !["Stop", "StopFailure", "IdlePrompt"].contains(event.event) { pending = false }
            if pending && activity == .working { activity = .waiting }
            let startsTurn = ["UserPromptSubmit", "TurnStarted"].contains(event.event)
            let turn = startsTurn ? event.turnID : event.turnID ?? sessions[key]?.turn
            let stopped = ["Stop", "SessionEnd"].contains(event.event)
                || (!startsTurn && sessions[key]?.stopped == true)
            sessions[key] = Session(agent: event.agent, sessionID: event.sessionID, turn: turn, time: event.time,
                                    activity: activity, decisionPending: pending,
                                    pid: event.pid ?? sessions[key]?.pid, stopped: stopped)
        }
        refresh(at: now)
        if snapshot.activity == .idle && activity == .idle {
            let interrupted = event.event == "Interrupt" || event.event == "IdlePrompt" || event.status == "interrupted"
            snapshot.cue = interrupted ? .interrupted : .stopped
            snapshot.cueID = event.eventID
            snapshot.cueDate = now
        } else if activity == .working {
            clearCue()
        }
    }

    public func activity(of ref: (agent: AgentKind, sessionID: String)) -> AgentActivity? {
        sessions[ref.agent.rawValue + ":" + ref.sessionID]?.activity
    }

    /// The session behind the colour the tube shows: the latest waiting,
    /// failed or finished session matching the combined activity.
    public func attentionTarget() -> AgentSessionRef? {
        let activity = snapshot.activity
        guard [.waiting, .failed, .finished].contains(activity) else { return nil }
        return sessions.values.filter { $0.activity == activity }
            .max { ($0.time, $0.sessionID) < ($1.time, $1.sessionID) }
            .map { AgentSessionRef(agent: $0.agent, sessionID: $0.sessionID, pid: $0.pid, activity: $0.activity) }
    }

    /// The user opened this session: a finished or failed outcome has been
    /// seen and becomes idle. A waiting session stays until answered.
    public mutating func markOpened(_ ref: AgentSessionRef, at now: Date = Date()) {
        let key = ref.agent.rawValue + ":" + ref.sessionID
        guard let activity = sessions[key]?.activity, activity == .finished || activity == .failed else { return }
        sessions[key]?.activity = .idle
        refresh(at: now)
    }

    public mutating func acknowledgeCompletion(at now: Date = Date()) {
        guard snapshot.activity == .finished else { return }
        for id in Array(sessions.keys) where sessions[id]?.activity == .finished { sessions[id]?.activity = .idle }
        clearCue()
        refresh(at: now)
    }

    public mutating func refresh(at now: Date = Date()) {
        let active = sessions.values.filter { $0.activity == .working || $0.activity == .waiting }
        snapshot.activeCount = active.count
        // Unseen results outrank ongoing work, so a finished session shows
        // even while others are still working; only a waiting session wins.
        if active.contains(where: { $0.activity == .waiting }) { snapshot.activity = .waiting }
        else if sessions.values.contains(where: { $0.activity == .failed }) { snapshot.activity = .failed }
        else if sessions.values.contains(where: { $0.activity == .finished }) { snapshot.activity = .finished }
        else if !active.isEmpty { snapshot.activity = .working }
        // A session that has started but done nothing yet carries no evidence;
        // it must not hide another session's outcome or idle state.
        else if sessions.isEmpty || !sessions.values.contains(where: { $0.activity != .unknown }) { snapshot.activity = .unknown }
        else { snapshot.activity = .idle }
        if snapshot.activity != .idle { clearCue() }
        if let date = snapshot.cueDate, now.timeIntervalSince(date) >= 3 { clearCue() }
    }

    private mutating func clearCue() {
        snapshot.cue = nil; snapshot.cueID = nil; snapshot.cueDate = nil
    }
}

/// A bounded visual test that never reaches the reducer. When it ends or is
/// cleared, the latest live snapshot shows through unchanged.
public struct AgentStatusPreview: Sendable {
    public private(set) var activity: AgentActivity?
    public private(set) var expires: Date?

    public init() {}

    public mutating func apply(_ event: AgentEvent, at now: Date = Date()) {
        guard event.event == "Preview", event.isValid(at: now), let status = event.status else { return }
        switch status {
        case "working": activity = .working
        case "waiting": activity = .waiting
        case "failed": activity = .failed
        case "finished": activity = .finished
        default: activity = nil; expires = nil; return
        }
        expires = now.addingTimeInterval(event.duration ?? 0)
    }

    public func isActive(at now: Date = Date()) -> Bool {
        guard activity != nil, let expires else { return false }
        return now < expires
    }

    /// A previewed green ends like a real completion.
    public mutating func acknowledgeCompletion() {
        if activity == .finished { activity = nil; expires = nil }
    }

    /// Clicking the tube during a preview ends it; nothing real is opened.
    public mutating func end() { activity = nil; expires = nil }

    public func overlay(_ live: AgentStatusSnapshot, at now: Date = Date()) -> AgentStatusSnapshot {
        guard isActive(at: now), let activity else { return live }
        return AgentStatusSnapshot(activity: activity, activeCount: live.activeCount)
    }
}

// Earlier names, kept so existing checks and call sites read unchanged.
public typealias CodexActivity = AgentActivity
public typealias CodexStatusCue = AgentStatusCue
public typealias CodexStatusSnapshot = AgentStatusSnapshot
public typealias CodexHookEvent = AgentEvent
public typealias CodexStatusReducer = AgentStatusReducer
