import AppKit
import Combine
import DelayCore
import SwiftUI

private let showStackNotification = Notification.Name("com.delaynomore.desktop.show-stack")

@main
@MainActor
enum DelayNoMoreMain {
    private static var retainedDelegate: AppDelegate?

    static func main() {
        let arguments = CommandLine.arguments
        func agentArgument(after flag: String) -> AgentKind? {
            guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
            return AgentKind(rawValue: arguments[index + 1])
        }
        // Hook helpers run first and fast; every other route is a manual tool.
        if let agent = agentArgument(after: "--agent-hook") {
            exit(AgentHookBridge.sendFromStandardInput(agent: agent))
        }
        if arguments.contains("--claude-statusline") {
            exit(AgentHookBridge.runClaudeStatusLine())
        }
        if arguments.contains("--codex-hook") {
            // Handlers installed by 1.8.x until they are refreshed.
            exit(AgentHookBridge.sendFromStandardInput(agent: .codex))
        }
        if arguments.contains("--usage-check") {
            // Reads Codex's weekly usage once through the same path as the tube.
            let done = DispatchSemaphore(value: 0)
            let monitor = CodexTurnMonitor { _ in }
            nonisolated(unsafe) var result: AgentUsage?
            monitor.requestRateLimits { reading in result = reading; done.signal() }
            _ = done.wait(timeout: .now() + 20)
            monitor.stop()
            guard let result else { print("No Codex weekly usage available."); exit(1) }
            let reset = result.resetsAt.map { " · resets \($0.formatted(.dateTime.weekday(.abbreviated).hour().minute()))" } ?? ""
            print("Codex weekly usage: \(result.displayPercent())%\(reset) (water \(Int(result.fillFraction() * 100))% full)")
            exit(0)
        }
        if arguments.contains("--codex-monitor-check") {
            exit(CodexTurnMonitor.runHeadlessCheck())
        }
        if arguments.contains("--connection-check") || arguments.contains("--codex-connection-check") {
            for agent in AgentKind.allCases {
                print("\(AgentHookBridge.displayName(agent)) hooks configured: \(AgentHookBridge.isInstalled(agent))")
            }
            print("Codex desktop process ancestry recognised: \(AgentHookBridge.isDesktopOwnedProcess())")
            exit(0)
        }
        if let index = arguments.firstIndex(of: "--status-preview") {
            let state = index + 1 < arguments.count ? arguments[index + 1] : ""
            let seconds = index + 2 < arguments.count ? Double(arguments[index + 2]) ?? 15 : 15
            guard AgentEvent.previewStates.contains(state), AgentHookBridge.sendPreview(state: state, seconds: min(60, max(1, seconds))) else {
                fputs("Usage: --status-preview working|waiting|failed|finished|clear [seconds, up to 60]\n", stderr); exit(1)
            }
            print("Sent a \(state) preview. Real agent status is unaffected.")
            exit(0)
        }
        if let agent = agentArgument(after: "--install-hooks") {
            do {
                try AgentHookBridge.install(agent, executable: Bundle.main.executableURL!)
                print("Installed \(AgentHookBridge.displayName(agent)) activity hooks. Review them in \(agent == .codex ? "Codex Settings > Hooks" : "Claude Code /hooks").")
                exit(0)
            } catch { fputs("Could not install hooks: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if let agent = agentArgument(after: "--remove-hooks") {
            do { try AgentHookBridge.uninstall(agent); print("Removed Delay No More \(AgentHookBridge.displayName(agent)) hooks."); exit(0) }
            catch { fputs("Could not remove hooks: \(error.localizedDescription)\n", stderr); exit(1) }
        }
        if CommandLine.arguments.contains("--self-test") {
            exit(StoreSelfTest.run())
        }
        if let bundleID = Bundle.main.bundleIdentifier,
           let existing = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier && !$0.isTerminated }) {
            DistributedNotificationCenter.default().postNotificationName(showStackNotification,
                                                                         object: nil, userInfo: nil,
                                                                         deliverImmediately: true)
            existing.activate(options: [.activateIgnoringOtherApps])
            return
        }
        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        let delegate = AppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.run()
    }
}

@MainActor
private final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    private var windowController: StackWindowController?
    private var taskStore: TaskStore?
    private var taskInteraction: AppInteraction?
    private var statusItem: NSStatusItem?
    private var storageErrorObservation: AnyCancellable?
    private var agentStatusObservation: AnyCancellable?
    private let agentStatus = AgentStatusStore()
    private let usage = AgentUsageStore()
    private var usageObservation: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        installMainMenu()
        let store = TaskStore()
        taskStore = store
        let interaction = AppInteraction()
        taskInteraction = interaction
        windowController = StackWindowController(store: store, interaction: interaction, agentStatus: agentStatus, usage: usage)
        DistributedNotificationCenter.default().addObserver(self, selector: #selector(showStack),
                                                            name: showStackNotification, object: nil)
        installStatusItem()
        agentStatus.onUsage = { [weak self] reading in self?.usage.receive(reading) }
        agentStatus.onCodexTurnCompleted = { [weak self] in self?.usage.codexTurnCompleted() }
        agentStatus.setListensForUsage(usage.source == .claude)
        agentStatus.start()
        windowController?.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        windowController?.show()
        return true
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let stackImage = NSImage(systemSymbolName: "square.stack.3d.up.fill", accessibilityDescription: "Delay No More")
        let errorImage = NSImage(systemSymbolName: "exclamationmark.triangle.fill", accessibilityDescription: "Storage problem")
        if let button = item.button {
            button.image = stackImage
            button.toolTip = "Delay No More"
            button.setAccessibilityLabel("Delay No More")
        }
        let menu = NSMenu()
        let show = NSMenuItem(title: "Show stack", action: #selector(showStack), keyEquivalent: "")
        show.target = self
        menu.addItem(show)
        let hide = NSMenuItem(title: "Hide stack", action: #selector(hideStack), keyEquivalent: "")
        hide.target = self
        menu.addItem(hide)
        let undo = NSMenuItem(title: "Undo task removal", action: #selector(undoTaskRemoval), keyEquivalent: "")
        undo.target = self
        menu.addItem(undo)
        menu.addItem(.separator())
        // Ticked = this agent's hooks are installed and its status is shown.
        for agent in AgentKind.allCases {
            let item = NSMenuItem(title: "\(AgentHookBridge.displayName(agent)) activity",
                                  action: #selector(toggleAgent(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = agent.rawValue
            menu.addItem(item)
        }
        menu.addItem(.separator())
        // Water level: one agent's usage limit, as radio choices.
        let waterHeader = NSMenuItem(title: "Water level", action: nil, keyEquivalent: "")
        waterHeader.isEnabled = false
        menu.addItem(waterHeader)
        for source in UsageSource.allCases {
            let title: String
            switch source {
            case .off: title = "Off"
            case .codex: title = "Codex weekly usage"
            case .claude: title = "Claude Code 5-hour usage"
            }
            let item = NSMenuItem(title: title, action: #selector(selectUsageSource(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = source.rawValue
            item.indentationLevel = 1
            menu.addItem(item)
        }
        let usageInfo = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        usageInfo.isEnabled = false
        usageInfo.indentationLevel = 1
        menu.addItem(usageInfo)
        usageObservation = usage.objectWillChange.prepend(()).sink { [weak self, weak usageInfo] _ in
            DispatchQueue.main.async {
                guard let self, let usageInfo else { return }
                usageInfo.title = self.usage.summary
                usageInfo.isHidden = self.usage.source == .off
            }
        }
        menu.addItem(.separator())
        let storageError = NSMenuItem(title: "Storage problem…", action: #selector(showStorageError), keyEquivalent: "")
        storageError.target = self
        storageError.isHidden = true
        menu.addItem(storageError)
        let retryLoad = NSMenuItem(title: "Retry loading saved stack", action: #selector(retryLoad), keyEquivalent: "")
        retryLoad.target = self
        retryLoad.isHidden = true
        menu.addItem(retryLoad)
        let quit = NSMenuItem(title: "Quit Delay No More", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        menu.addItem(quit)
        item.menu = menu
        statusItem = item
        agentStatusObservation = agentStatus.$snapshot.removeDuplicates().sink { [weak item] snapshot in
            item?.button?.setAccessibilityValue(snapshot.accessibilityDescription)
        }
        storageErrorObservation = taskStore?.$error.sink { [weak self, weak item] error in
            storageError.isHidden = error == nil
            retryLoad.isHidden = error == nil || self?.taskStore?.canEdit != false
            item?.button?.image = error == nil ? stackImage : errorImage
            item?.button?.toolTip = error ?? "Delay No More"
            item?.button?.setAccessibilityLabel(error == nil ? "Delay No More" : "Delay No More, storage problem")
        }
    }

    private func installMainMenu() {
        let menu = NSMenu()
        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Delay No More")
        appMenu.addItem(withTitle: "Quit Delay No More", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func agent(of item: NSMenuItem) -> AgentKind? {
        (item.representedObject as? String).flatMap(AgentKind.init(rawValue:))
    }

    @objc private func selectUsageSource(_ sender: NSMenuItem) {
        guard let source = (sender.representedObject as? String).flatMap(UsageSource.init(rawValue:)),
              source != usage.source else { return }
        do {
            // Claude Code shares usage only with its status-line command.
            if source == .claude, let executable = Bundle.main.executableURL {
                try AgentHookBridge.installStatusLine(executable: executable)
            }
            if usage.source == .claude, source != .claude { try AgentHookBridge.uninstallStatusLine() }
        } catch { showConnectionError(error); return }
        usage.select(source)
        agentStatus.setListensForUsage(source == .claude)
    }

    @objc private func toggleAgent(_ sender: NSMenuItem) {
        guard let agent = agent(of: sender) else { return }
        if AgentHookBridge.isInstalled(agent) {
            do {
                try AgentHookBridge.uninstall(agent)
                agentStatus.updateConnections()
            } catch { showConnectionError(error) }
            return
        }
        guard let executable = Bundle.main.executableURL else { return }
        do {
            try AgentHookBridge.install(agent, executable: executable)
            agentStatus.updateConnections()
            let alert = NSAlert()
            alert.messageText = "Review the \(AgentHookBridge.displayName(agent)) connection"
            alert.informativeText = agent == .codex
                ? "In Codex, open Settings > Hooks and review and trust the Delay No More activity hooks. The tube observes new local activity after trust. Existing hooks are preserved."
                : "Claude Code reads hooks when a session starts. New sessions report activity; in a running session, open /hooks to review them. Existing settings are preserved."
            if let error = agentStatus.connectionError { alert.informativeText += "\n\nLocal connection problem: \(error)" }
            alert.addButton(withTitle: "Done")
            alert.runModal()
        } catch { showConnectionError(error) }
    }

    private func showConnectionError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Couldn’t update the agent connection"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showStack() { windowController?.show() }
    @objc private func hideStack() { windowController?.hide() }
    @objc private func retryLoad() { taskStore?.retryLoad() }

    @objc private func showStorageError() {
        guard let error = taskStore?.error else { return }
        let alert = NSAlert()
        alert.messageText = "Storage problem"
        alert.informativeText = error
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private var canUndoTaskRemoval: Bool {
        taskStore?.undoName != nil && taskInteraction?.cardFlightActive == false && taskInteraction?.draggingCard == false
    }

    @objc private func undoTaskRemoval() {
        if canUndoTaskRemoval { taskStore?.undoRemoval() }
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(undoTaskRemoval) { return canUndoTaskRemoval }
        if menuItem.action == #selector(selectUsageSource(_:)) {
            menuItem.state = (menuItem.representedObject as? String) == usage.source.rawValue ? .on : .off
            return true
        }
        if menuItem.action == #selector(toggleAgent(_:)) {
            menuItem.state = agent(of: menuItem).map(AgentHookBridge.isInstalled) == true ? .on : .off
            return true
        }
        return true
    }
}
