import Darwin
import DelayCore
import Foundation

/// A short, fail-open hook helper shared by Codex and Claude Code. It never
/// returns agent instructions or an approval decision and never persists the
/// hook's full input: only event name, session/turn IDs, time and owner PID.
enum AgentHookBridge {
    static let marker = "--delay-no-more-status-v2"
    /// Handlers installed by 1.8.x; recognised so they are replaced, not duplicated.
    static let legacyMarker = "--codex-hook --delay-no-more-status-v1"

    static func events(for agent: AgentKind) -> [String] {
        switch agent {
        case .codex:
            return ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "Stop", "Interrupt",
                    "SessionEnd", "PermissionRequest", "PreModelRequest"]
        case .claude:
            return ["SessionStart", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure",
                    "PermissionRequest", "PermissionDenied", "Notification", "Stop", "StopFailure", "SessionEnd"]
        }
    }

    static func displayName(_ agent: AgentKind) -> String { agent == .codex ? "Codex" : "Claude Code" }

    static var socketURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DelayNoMore/codex.sock")
    }

    static func configURL(for agent: AgentKind) -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        switch agent {
        case .codex: return home.appendingPathComponent(".codex/hooks.json")
        case .claude: return home.appendingPathComponent(".claude/settings.json")
        }
    }

    static func isInstalled(_ agent: AgentKind) -> Bool { isInstalled(agent, at: configURL(for: agent)) }
    static var anyInstalled: Bool { AgentKind.allCases.contains(where: isInstalled) }

    static func isInstalled(_ agent: AgentKind, at url: URL) -> Bool {
        guard let root = try? readConfiguration(url), let hooks = root["hooks"] as? [String: Any] else { return false }
        return events(for: agent).allSatisfy { event in
            guard let groups = hooks[event] as? [[String: Any]] else { return false }
            return groups.contains { group in
                (group["hooks"] as? [[String: Any]])?.contains(where: { isOwned($0, agent: agent) }) == true
            }
        }
    }

    // MARK: Projection

    static func filteredEvent(agent: AgentKind, from data: Data, pid: Int32? = nil, now: Date = Date()) -> AgentEvent? {
        guard data.count <= 4_194_304,
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let incoming = input["hook_event_name"] as? String,
              let session = input["session_id"] as? String,
              events(for: agent).contains(incoming) else { return nil }
        // Subagent work is covered by its parent turn, which stays active until
        // the parent finishes. A subagent session would never get an outcome.
        if input["agent_id"] != nil { return nil }
        let tool = input["tool_name"] as? String ?? ""
        let event: String?
        switch agent {
        case .codex:
            let asynchronous = tool == "request_user_input_async" || tool.hasSuffix("__request_user_input_async") || tool.hasSuffix(".request_user_input_async")
            let decisionTool = tool == "request_user_input" || tool.hasSuffix("__request_user_input") || tool.hasSuffix(".request_user_input")
            event = incoming == "PreToolUse" && asynchronous ? "DecisionRequestAsync"
                : incoming == "PreToolUse" && decisionTool ? "DecisionRequest" : incoming
        case .claude:
            switch incoming {
            case "PreToolUse": event = tool == "AskUserQuestion" ? "DecisionRequest" : "PreToolUse"
            case "PostToolUseFailure", "PermissionDenied": event = "PostToolUse"
            case "Notification":
                switch input["notification_type"] as? String {
                case "permission_prompt", "elicitation_dialog": event = "DecisionRequest"
                case "idle_prompt": event = "IdlePrompt"
                default: event = nil
                }
            default: event = incoming
            }
        }
        guard let event else { return nil }
        let value = AgentEvent(agent: agent, sessionID: session, turnID: input["turn_id"] as? String,
                               event: event, time: now.timeIntervalSince1970, pid: pid)
        return value.isValid(at: now) ? value : nil
    }

    static func sendFromStandardInput(agent: AgentKind) -> Int32 {
        // Stop expects JSON on stdout. Empty JSON is valid for every hooked event.
        defer { print("{}") }
        if agent == .codex, !isDesktopOwnedProcess() { return 0 }
        guard let input = readInput(),
              let event = filteredEvent(agent: agent, from: input, pid: ownerProcessID()),
              let payload = try? JSONEncoder().encode(event) else { return 0 }
        send(payload, to: socketURL)
        return 0
    }

    /// Sends a preview to the running app. Previews never reach real status.
    static func sendPreview(state: String, seconds: Double) -> Bool {
        let event = AgentEvent(sessionID: "preview", event: "Preview", status: state,
                               duration: state == "clear" ? nil : seconds)
        guard event.isValid(at: Date()), let payload = try? JSONEncoder().encode(event) else { return false }
        send(payload, to: socketURL)
        return true
    }

    // MARK: Process ancestry

    private static func executablePath(_ pid: pid_t) -> String? {
        var path = [CChar](repeating: 0, count: 4096)
        guard proc_pidpath(pid, &path, UInt32(path.count)) > 0 else { return nil }
        return String(cString: path)
    }

    private static func parent(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout.size(ofValue: info))
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size,
              info.pbi_ppid != UInt32(pid) else { return nil }
        return pid_t(info.pbi_ppid)
    }

    /// The agent process that ran this hook: the first ancestor that is not a
    /// shell wrapper. If it exits, its sessions can never report an outcome.
    static func ownerProcessID() -> Int32? {
        let shells: Set<String> = ["sh", "bash", "zsh", "dash", "fish", "env", "timeout"]
        var pid = getppid()
        for _ in 0..<8 {
            guard pid > 1 else { return nil }
            guard let path = executablePath(pid) else { return nil }
            if !shells.contains(URL(fileURLWithPath: path).lastPathComponent) { return pid }
            guard let next = parent(of: pid) else { return nil }
            pid = next
        }
        return nil
    }

    /// Positive executable ancestry, independent of chat text or UI inspection.
    /// A CLI explicitly launched from the desktop's bundled binary shares this
    /// ownership. Unrecognised/missing ancestry is ignored conservatively.
    static func isDesktopOwnedProcess() -> Bool {
        var pid = getppid()
        for _ in 0..<32 {
            guard pid > 1 else { break }
            if let executable = executablePath(pid) {
                if let range = executable.range(of: ".app/Contents/") {
                    let appPath = String(executable[..<range.lowerBound]) + ".app"
                    let id = Bundle(path: appPath)?.bundleIdentifier
                    if id == "com.openai.chat" || id == "com.openai.codex" { return true }
                }
                // A standalone Codex process does not become a desktop session
                // merely because its terminal was opened by the desktop app.
                if URL(fileURLWithPath: executable).lastPathComponent == "codex" { return false }
            }
            guard let next = parent(of: pid) else { break }
            pid = next
        }
        return false
    }

    private static func readInput() -> Data? {
        let deadline = ProcessInfo.processInfo.systemUptime + 0.3
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16384)
        while ProcessInfo.processInfo.systemUptime < deadline {
            var poller = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
            guard poll(&poller, 1, 10) > 0 else { continue }
            let count = read(STDIN_FILENO, &buffer, buffer.count)
            if count == 0 { return data }
            guard count > 0, data.count + count <= 4_194_304 else { return nil }
            data.append(contentsOf: buffer.prefix(count))
        }
        return nil
    }

    static func send(_ data: Data, to url: URL) {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let path = Array(url.path.utf8CString)
        guard path.count <= MemoryLayout.size(ofValue: address.sun_path) else { return }
        withUnsafeMutableBytes(of: &address.sun_path) { destination in path.withUnsafeBytes { destination.copyBytes(from: $0) } }
        let descriptor = socket(AF_UNIX, SOCK_DGRAM, 0)
        guard descriptor >= 0 else { return }
        defer { close(descriptor) }
        _ = fcntl(descriptor, F_SETFL, O_NONBLOCK)
        data.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) { pointer in
                _ = pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, buffer.baseAddress, data.count, 0, $0, socklen_t(MemoryLayout<sockaddr_un>.size))
                }
            }
        }
    }

    // MARK: Configuration

    static func command(agent: AgentKind, executable: URL) -> String {
        let quoted = "'" + executable.path.replacingOccurrences(of: "'", with: "'\\''") + "'"
        return quoted + " --agent-hook \(agent.rawValue) " + marker
    }

    static func install(_ agent: AgentKind, executable: URL, configURL url: URL? = nil) throws {
        let url = url ?? configURL(for: agent)
        var root = try readConfiguration(url)
        var hooks = try hookTable(root)
        removeOwned(from: &hooks, agent: agent)
        let command = command(agent: agent, executable: executable)
        for event in events(for: agent) {
            var groups = hooks[event] as? [[String: Any]] ?? []
            groups.append(["hooks": [["type": "command", "command": command, "timeout": 1]]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        try writeConfiguration(root, to: url)
    }

    static func uninstall(_ agent: AgentKind, configURL url: URL? = nil) throws {
        let url = url ?? configURL(for: agent)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        var root = try readConfiguration(url)
        var hooks = try hookTable(root)
        removeOwned(from: &hooks, agent: agent)
        if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        try writeConfiguration(root, to: url)
    }

    private static func isOwned(_ handler: [String: Any], agent: AgentKind) -> Bool {
        guard handler["type"] as? String == "command", let command = handler["command"] as? String else { return false }
        if command.hasSuffix(" --agent-hook \(agent.rawValue) " + marker) { return true }
        return agent == .codex && command.hasSuffix(" " + legacyMarker)
    }

    private static func removeOwned(from table: inout [String: Any], agent: AgentKind) {
        for event in Array(table.keys) {
            guard let groups = table[event] as? [[String: Any]] else { continue }
            let retainedGroups = groups.compactMap { group -> [String: Any]? in
                guard let handlers = group["hooks"] as? [[String: Any]] else { return group }
                let retained = handlers.filter { !isOwned($0, agent: agent) }
                guard !retained.isEmpty else { return nil }
                var copy = group; copy["hooks"] = retained; return copy
            }
            if retainedGroups.isEmpty { table.removeValue(forKey: event) } else { table[event] = retainedGroups }
        }
    }

    private static func readConfiguration(_ url: URL) throws -> [String: Any] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        let data = try Data(contentsOf: url)
        guard let value = try JSONSerialization.jsonObject(with: data) as? [String: Any] else { throw configurationError() }
        _ = try hookTable(value)
        return value
    }

    private static func hookTable(_ root: [String: Any]) throws -> [String: Any] {
        guard let value = root["hooks"] else { return [:] }
        guard let table = value as? [String: Any], table.values.allSatisfy({ value in
            guard let groups = value as? [[String: Any]] else { return false }
            return groups.allSatisfy { $0["hooks"] is [[String: Any]] }
        }) else { throw configurationError() }
        return table
    }

    private static func configurationError() -> NSError {
        NSError(domain: "Agent connection", code: 3,
                userInfo: [NSLocalizedDescriptionKey: "The existing hooks file is unreadable or has an unsupported structure. It has been preserved."])
    }

    private static func writeConfiguration(_ root: [String: Any], to url: URL) throws {
        let data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if let original = try? Data(contentsOf: url) {
            // An unchanged install neither creates another backup nor changes trust.
            if let decoded = try? JSONSerialization.jsonObject(with: original) as? NSDictionary,
               decoded.isEqual(to: root) { return }
            let stem = url.deletingPathExtension().lastPathComponent
            let backup = url.deletingLastPathComponent()
                .appendingPathComponent("\(stem).delay-no-more.\(UUID().uuidString).backup.json")
            try original.write(to: backup, options: .withoutOverwriting)
            guard try Data(contentsOf: backup) == original else { throw configurationError() }
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
}
