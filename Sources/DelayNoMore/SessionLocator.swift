import AppKit
import DelayCore
import Darwin

/// Where an agent session lives on screen, worked out from its owner process.
struct SessionLocation: Equatable {
    /// Terminal device, e.g. `/dev/ttys001`, when the agent runs in a terminal.
    var tty: String?
    /// The app hosting the session, e.g. iTerm2.
    var hostBundleID: String?
    var hostPID: pid_t?
}

/// Takes the user to an agent session. Nothing here runs in the background:
/// `locate` runs once when a session needs attention, `open` only on a click.
@MainActor
enum SessionLocator {
    static let iTermBundleID = "com.googlecode.iterm2"
    static let terminalBundleID = "com.apple.Terminal"

    // MARK: Locating

    /// Reads the owner process's terminal and walks up to its host app with
    /// two sysctl calls per ancestor; no child processes.
    static func locate(pid: Int32) -> SessionLocation? {
        guard let owner = processInfo(pid) else { return nil }
        var location = SessionLocation(tty: ttyPath(owner.tdev))
        var current = pid
        for _ in 0..<16 {
            guard current > 1 else { break }
            if let app = NSRunningApplication(processIdentifier: current), let bundle = app.bundleIdentifier {
                location.hostBundleID = bundle
                location.hostPID = current
                return location
            }
            // iTerm2 keeps sessions in iTermServer helpers that can outlive a
            // restarted iTerm2 and get reparented to launchd.
            if executablePath(current)?.contains("/iTerm2/iTermServer") == true {
                location.hostBundleID = iTermBundleID
            }
            guard let parent = processInfo(current)?.ppid, parent != current else { break }
            current = parent
        }
        return location.tty == nil && location.hostBundleID == nil ? nil : location
    }

    private static func processInfo(_ pid: Int32) -> (ppid: Int32, tdev: dev_t)? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0, info.kp_proc.p_pid == pid else { return nil }
        return (info.kp_eproc.e_ppid, info.kp_eproc.e_tdev)
    }

    private static func ttyPath(_ device: dev_t) -> String? {
        guard device != -1, let name = devname(device, S_IFCHR) else { return nil }
        let path = "/dev/" + String(cString: name)
        return isValidTTY(path) ? path : nil
    }

    private static func executablePath(_ pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    // MARK: Validation (everything placed into a URL or script is checked)

    static func isValidTTY(_ path: String) -> Bool {
        path.range(of: #"^/dev/ttys[0-9]{1,4}$"#, options: .regularExpression) != nil
    }

    static func codexThreadURL(_ threadID: String) -> URL? {
        guard !threadID.isEmpty, threadID.utf8.count <= 128,
              threadID.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else { return nil }
        return URL(string: "codex://threads/" + threadID)
    }

    /// AppleScript that brings forward the tab whose session uses `tty`.
    static func focusScript(bundleID: String, tty: String) -> String? {
        guard isValidTTY(tty) else { return nil }
        switch bundleID {
        case iTermBundleID:
            return """
            tell application id "\(iTermBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        repeat with s in sessions of t
                            if tty of s is "\(tty)" then
                                select w
                                select t
                                select s
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end tell
            return false
            """
        case terminalBundleID:
            return """
            tell application id "\(terminalBundleID)"
                repeat with w in windows
                    repeat with t in tabs of w
                        if tty of t is "\(tty)" then
                            set selected tab of w to t
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end tell
            return false
            """
        default:
            return nil
        }
    }

    // MARK: Opening

    enum Outcome: String { case thread, tab, app, nothing }

    @discardableResult
    static func open(_ ref: AgentSessionRef, location: SessionLocation?) -> Outcome {
        if ref.agent == .codex {
            guard let url = codexThreadURL(ref.sessionID) else { return .nothing }
            return NSWorkspace.shared.open(url) ? .thread : .nothing
        }
        guard let location else { return .nothing }
        if let bundle = location.hostBundleID, let tty = location.tty,
           let source = focusScript(bundleID: bundle, tty: tty),
           NSRunningApplication.runningApplications(withBundleIdentifier: bundle).isEmpty == false {
            var error: NSDictionary?
            let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
            if error == nil, result?.booleanValue == true { return .tab }
        }
        return activateHost(location) ? .app : .nothing
    }

    private static func activateHost(_ location: SessionLocation) -> Bool {
        let app = location.hostPID.flatMap { NSRunningApplication(processIdentifier: $0) }
            ?? location.hostBundleID.flatMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }
        guard let app else { return false }
        return app.activate(options: [.activateAllWindows])
    }
}
