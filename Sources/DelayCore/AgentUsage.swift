import Foundation

/// Which agent's usage limit the tube's water shows.
public enum UsageSource: String, CaseIterable, Sendable {
    case off, codex, claude

    public var agent: AgentKind? {
        switch self {
        case .off: return nil
        case .codex: return .codex
        case .claude: return .claude
        }
    }
}

/// One usage-limit window: how much is used and when it resets. Contains no
/// account, plan, credit or conversation data.
public struct AgentUsage: Codable, Equatable, Sendable {
    public let agent: AgentKind
    public let usedPercent: Double
    public let resetsAt: Date?
    public let observedAt: Date

    /// Claude Code shows its 5-hour limit; Codex shows its weekly limit.
    public static func windowName(for agent: AgentKind) -> String {
        agent == .claude ? "5-hour" : "weekly"
    }

    static let codexWindowMinutes = 10_080

    public init(agent: AgentKind, usedPercent: Double, resetsAt: Date?, observedAt: Date = Date()) {
        self.agent = agent; self.usedPercent = usedPercent
        self.resetsAt = resetsAt; self.observedAt = observedAt
    }

    /// 0 … 1 water level showing what is LEFT: full when nothing is used,
    /// empty when the limit is used up, full again once the window resets.
    public func fillFraction(at now: Date = Date()) -> Double {
        if let resetsAt, resetsAt <= now { return 1 }
        guard usedPercent.isFinite else { return 0 }
        return min(1, max(0, 1 - usedPercent / 100))
    }

    /// Percent of the limit left, shown in text; 100 after the window resets.
    public func remainingPercent(at now: Date = Date()) -> Int {
        Int((fillFraction(at: now) * 100).rounded())
    }

    /// Claude Code status-line input: only `rate_limits.five_hour` is read.
    public static func fromClaudeStatusLine(_ input: [String: Any], now: Date = Date()) -> AgentUsage? {
        guard let limits = input["rate_limits"] as? [String: Any],
              let window = limits["five_hour"] as? [String: Any],
              let percent = number(window["used_percentage"]), percent.isFinite, percent >= 0 else { return nil }
        let reset = number(window["resets_at"]).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
        return AgentUsage(agent: .claude, usedPercent: percent, resetsAt: reset, observedAt: now)
    }

    /// Codex `account/rateLimits/read` result: only the weekly window is read,
    /// from whichever slot holds it.
    public static func fromCodexRateLimits(_ result: [String: Any], now: Date = Date()) -> AgentUsage? {
        guard let limits = result["rateLimits"] as? [String: Any] else { return nil }
        for slot in ["primary", "secondary"] {
            guard let window = limits[slot] as? [String: Any],
                  number(window["windowDurationMins"]).map(Int.init) == codexWindowMinutes,
                  let percent = number(window["usedPercent"]), percent.isFinite, percent >= 0 else { continue }
            let reset = number(window["resetsAt"]).flatMap { $0.isFinite ? Date(timeIntervalSince1970: $0) : nil }
            return AgentUsage(agent: .codex, usedPercent: percent, resetsAt: reset, observedAt: now)
        }
        return nil
    }

    /// The Claude Code status-line text, e.g. `5h 58% left`.
    public static func claudeStatusLineText(_ usage: AgentUsage?, now: Date = Date()) -> String {
        guard let usage else { return "" }
        return "5h \(usage.remainingPercent(at: now))% left"
    }

    private static func number(_ value: Any?) -> Double? {
        if let value = value as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID() { return value.doubleValue }
        return nil
    }
}
