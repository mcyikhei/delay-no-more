import DelayCore
import Foundation

/// Usage water: projections, fill level, persistence and status-line setup.
@MainActor
enum UsageSelfTest {
    static func run(check: (Bool, String) -> Void) {
        let now = Date()
        let soon = now.timeIntervalSince1970 + 3_600

        // Claude Code status line.
        let statusInput: [String: Any] = [
            "model": ["display_name": "PRIVATE"], "cwd": "/PRIVATE",
            "context_window": ["used_percentage": 88],
            "rate_limits": ["five_hour": ["used_percentage": 42.4, "resets_at": soon],
                            "seven_day": ["used_percentage": 90, "resets_at": soon + 86_400]]
        ]
        let claude = AgentUsage.fromClaudeStatusLine(statusInput, now: now)
        check(claude?.agent == .claude && claude?.usedPercent == 42.4
              && claude?.resetsAt == Date(timeIntervalSince1970: soon),
              "Claude usage reads the 5-hour window, not the weekly or context figures")
        check(AgentUsage.claudeStatusLineText(claude, now: now) == "5h 42%", "Claude status line prints exactly 5h 42%")
        check(AgentUsage.fromClaudeStatusLine(["model": ["id": "x"]]) == nil
              && AgentUsage.claudeStatusLineText(nil) == "",
              "without rate limits the status line has no usage and prints nothing")

        // Codex rate limits (shape confirmed against the installed app-server).
        func codexResult(_ primary: [String: Any]?, _ secondary: [String: Any]? = nil) -> [String: Any] {
            var limits: [String: Any] = ["limitId": "codex", "planType": "PRIVATE",
                                         "credits": ["balance": "PRIVATE"], "secondary": NSNull()]
            limits["primary"] = primary ?? NSNull()
            if let secondary { limits["secondary"] = secondary }
            return ["accountId": "PRIVATE", "rateLimits": limits]
        }
        let weekly: [String: Any] = ["usedPercent": 99, "windowDurationMins": 10_080, "resetsAt": soon]
        let fiveHour: [String: Any] = ["usedPercent": 10, "windowDurationMins": 300, "resetsAt": soon]
        check(AgentUsage.fromCodexRateLimits(codexResult(weekly))?.usedPercent == 99, "Codex usage reads the weekly window")
        check(AgentUsage.fromCodexRateLimits(codexResult(fiveHour, weekly))?.usedPercent == 99,
              "Codex finds the weekly window in either slot and ignores the 5-hour one")
        check(AgentUsage.fromCodexRateLimits(codexResult(fiveHour)) == nil, "Codex without a weekly window shows no usage")
        if let reading = AgentUsage.fromCodexRateLimits(codexResult(weekly)),
           let text = String(data: (try? JSONEncoder().encode(AgentEvent.usage(reading))) ?? Data(), encoding: .utf8) {
            check(!text.contains("PRIVATE"), "usage readings carry no account, plan or credit data")
        } else { check(false, "Codex usage projection") }

        // Fill level.
        check(AgentUsage(agent: .codex, usedPercent: 50, resetsAt: nil).fillFraction() == 0.5, "50% usage fills half the tube")
        check(AgentUsage(agent: .codex, usedPercent: 130, resetsAt: nil).fillFraction() == 1, "usage over 100% fills the tube, no more")
        let expired = AgentUsage(agent: .claude, usedPercent: 80, resetsAt: now.addingTimeInterval(-1))
        check(expired.fillFraction(at: now) == 0 && expired.displayPercent(at: now) == 0,
              "after the window resets the tube is empty")

        // Usage events never touch agent status.
        var reducer = AgentStatusReducer()
        reducer.receive(AgentEvent(agent: .claude, sessionID: "s", event: "UserPromptSubmit"))
        let before = reducer.snapshot
        let usageEvent = AgentEvent.usage(AgentUsage(agent: .claude, usedPercent: 42, resetsAt: Date(timeIntervalSince1970: soon)))
        check(usageEvent.isValid(at: Date()), "usage events validate")
        reducer.receive(usageEvent)
        check(reducer.snapshot == before, "a usage reading never changes agent status")
        check(!AgentEvent(agent: .claude, sessionID: "usage", event: "Usage", usedPercent: .nan).isValid(at: Date()),
              "malformed usage readings are rejected")
        check(usageEvent.usageReading?.usedPercent == 42, "usage readings round-trip through the socket event")

        // Store: selection, persistence and per-agent readings.
        let suite = "dnm-usage-test-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { check(false, "usage defaults suite"); return }
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = AgentUsageStore(defaults: defaults, requestCodex: { $0(nil) })
        check(store.source == .off && store.fraction == 0, "water starts off")
        store.receive(AgentUsage(agent: .claude, usedPercent: 60, resetsAt: Date(timeIntervalSince1970: soon)))
        check(store.fraction == 0, "readings for an unselected agent don't fill the tube")
        store.select(.claude)
        check(store.fraction == 0.6 && store.summary.hasPrefix("60% used"), "selecting Claude shows its last reading at once")
        store.select(.off)
        check(store.fraction == 0 && store.summary.isEmpty, "Off empties the tube")
        store.select(.claude)
        let reopened = AgentUsageStore(defaults: defaults, requestCodex: { $0(nil) })
        check(reopened.source == .claude && reopened.fraction == 0.6, "selection and last reading survive a restart")
        reopened.select(.codex)
        check(reopened.summary == "Waiting for usage…", "a source without a reading says it is waiting")

        // Claude Code status-line setup.
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("dnm-statusline-\(UUID().uuidString)")
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: directory) }
            let url = directory.appendingPathComponent("settings.json")
            try Data(#"{"theme":"dark","hooks":{}}"#.utf8).write(to: url)
            let executable = directory.appendingPathComponent("Delay No More.app/Contents/MacOS/DelayNoMore")
            try AgentHookBridge.installStatusLine(executable: executable, configURL: url)
            check(AgentHookBridge.statusLineOwner(configURL: url) == .delayNoMore, "status line installs")
            let first = try Data(contentsOf: url)
            try AgentHookBridge.installStatusLine(executable: executable, configURL: url)
            check(try Data(contentsOf: url) == first, "status line setup is idempotent")
            let root = try JSONSerialization.jsonObject(with: first) as! [String: Any]
            check(root["theme"] as? String == "dark" && root["hooks"] != nil, "status line setup keeps other settings")
            try AgentHookBridge.uninstallStatusLine(configURL: url)
            let removed = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
            check(removed["statusLine"] == nil && removed["theme"] as? String == "dark", "status line removal keeps other settings")

            let foreign = Data(#"{"statusLine":{"type":"command","command":"my-own-line"}}"#.utf8)
            try foreign.write(to: url)
            var refused = false
            do { try AgentHookBridge.installStatusLine(executable: executable, configURL: url) } catch { refused = true }
            try AgentHookBridge.uninstallStatusLine(configURL: url)
            check(refused && (try? Data(contentsOf: url)) == foreign, "the user's own status line is never replaced or removed")
        } catch { check(false, "status line fixtures: \(error.localizedDescription)") }
    }
}
