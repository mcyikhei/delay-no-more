import Combine
import DelayCore
import Foundation

/// Which agent's usage the water shows, plus the latest reading for it.
/// Codex is read every 5 minutes only while selected; Claude Code readings
/// arrive from its status line. Nothing here polls when the water is off.
@MainActor
final class AgentUsageStore: ObservableObject {
    @Published private(set) var source: UsageSource
    @Published private(set) var usage: AgentUsage?
    /// 0 … 1 water level for the selected source.
    @Published private(set) var fraction: Double = 0

    private let defaults: UserDefaults
    private var readings: [AgentKind: AgentUsage] = [:]
    private var codexTask: Task<Void, Never>?
    private var resetTask: Task<Void, Never>?
    private let requestCodex: (@escaping @Sendable (AgentUsage?) -> Void) -> Void
    private static let sourceKey = "usageSource"
    private static let readingsKey = "usageReadings"
    static let codexInterval: UInt64 = 300

    init(defaults: UserDefaults = .standard,
         requestCodex: ((@escaping @Sendable (AgentUsage?) -> Void) -> Void)? = nil) {
        self.defaults = defaults
        source = defaults.string(forKey: Self.sourceKey).flatMap(UsageSource.init(rawValue:)) ?? .off
        if let data = defaults.data(forKey: Self.readingsKey),
           let saved = try? JSONDecoder().decode([String: AgentUsage].self, from: data) {
            for (key, value) in saved { if let agent = AgentKind(rawValue: key) { readings[agent] = value } }
        }
        if let requestCodex {
            self.requestCodex = requestCodex
        } else {
            let monitor = CodexTurnMonitor { _ in }
            self.requestCodex = { completion in monitor.requestRateLimits(completion: completion) }
        }
        publish()
        if source == .codex { startCodexReads() }
    }

    func select(_ newSource: UsageSource) {
        guard newSource != source else { return }
        source = newSource
        defaults.set(newSource.rawValue, forKey: Self.sourceKey)
        codexTask?.cancel(); codexTask = nil
        if newSource == .codex { startCodexReads() }
        publish()
    }

    /// A reading from either agent. Kept even when not selected, so switching
    /// shows the last known level at once.
    func receive(_ reading: AgentUsage) {
        readings[reading.agent] = reading
        let encoded = Dictionary(uniqueKeysWithValues: readings.map { ($0.key.rawValue, $0.value) })
        if let data = try? JSONEncoder().encode(encoded) { defaults.set(data, forKey: Self.readingsKey) }
        if reading.agent == source.agent { publish() }
    }

    /// A Codex turn just ended, which is when its usage changes.
    func codexTurnCompleted() {
        if source == .codex { readCodexNow() }
    }

    private func startCodexReads() {
        codexTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.readCodexNow()
                do { try await Task.sleep(nanoseconds: Self.codexInterval * 1_000_000_000) } catch { return }
            }
        }
    }

    private func readCodexNow() {
        requestCodex { reading in
            Task { @MainActor [weak self] in
                if let reading { self?.receive(reading) }
            }
        }
    }

    private func publish() {
        let current = source.agent.flatMap { readings[$0] }
        if usage != current { usage = current }
        let level = current?.fillFraction() ?? 0
        if fraction != level { fraction = level }
        // Drain the water when the window resets; no periodic timer.
        resetTask?.cancel(); resetTask = nil
        if let reset = current?.resetsAt, reset > Date() {
            resetTask = Task { [weak self] in
                let delay = reset.timeIntervalSinceNow + 1
                do { try await Task.sleep(nanoseconds: UInt64(max(0, delay) * 1_000_000_000)) } catch { return }
                self?.publish()
            }
        }
    }

    /// Menu text, e.g. `42% used · resets 14:30`.
    var summary: String {
        guard source != .off else { return "" }
        guard let usage else { return "Waiting for usage…" }
        var text = "\(usage.displayPercent())% used"
        if let reset = usage.resetsAt, reset > Date() {
            let format: Date.FormatStyle = reset.timeIntervalSinceNow > 20 * 3600
                ? .dateTime.weekday(.abbreviated).hour().minute()
                : .dateTime.hour().minute()
            text += " · resets \(reset.formatted(format))"
        }
        return text
    }

    var accessibilityDescription: String? {
        guard let agent = source.agent, let usage else { return nil }
        return "\(AgentHookBridge.displayName(agent)) \(AgentUsage.windowName(for: agent)) usage \(usage.displayPercent())%"
    }
}
