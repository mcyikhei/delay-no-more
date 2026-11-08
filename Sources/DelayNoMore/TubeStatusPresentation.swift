import SwiftUI
import DelayCore

/// Visual state only. Task data, tube geometry and input regions are independent.
/// Every state is a still pose: the pet is usually tucked at a screen edge, so
/// status never animates and an idle or busy tube costs no redraws.
struct TubeStatusAppearance: Equatable {
    /// Glowing outline around the glass, rim and base; nil leaves plain glass.
    var glowColor: Color?
    var reflectionStrength: Double = 0.45
    var eyeOpenness: CGFloat = 1
    var eyeOffset: CGFloat = 0
    var eyeVerticalOffset: CGFloat = 0
    var thinkingEyes = false
    var mouthCurve: CGFloat = 1
    var browAngle: Double = 0
    var showsBrows = false

    static let neutral = TubeStatusAppearance()

    static func make(activity: AgentActivity, cue: AgentStatusCue?) -> TubeStatusAppearance {
        var pose = TubeStatusAppearance()
        switch activity {
        case .unknown:
            pose.eyeOpenness = 0.4
            pose.mouthCurve = 0.3
            pose.reflectionStrength = 0.2
        case .idle:
            break
        case .working:
            pose.glowColor = StackTheme.codexWorking
            pose.reflectionStrength = 0.8
            pose.thinkingEyes = true
            pose.eyeVerticalOffset = -2.5
            pose.mouthCurve = 0.5
        case .failed:
            pose.glowColor = StackTheme.codexFailed
            pose.eyeOpenness = 0.8
            pose.showsBrows = true
            pose.browAngle = -20
            pose.mouthCurve = -0.8
        case .waiting:
            pose.glowColor = StackTheme.codexWaiting
            pose.eyeOpenness = 1.15
            pose.showsBrows = true
            pose.browAngle = 10
            pose.mouthCurve = 0.3
        case .finished:
            pose.glowColor = StackTheme.codexFinished
            pose.mouthCurve = 1.2
        }
        guard activity == .idle, let cue else { return pose }
        switch cue {
        case .stopped:
            pose.eyeOpenness = 0.55
            pose.mouthCurve = 0.6
        case .interrupted:
            pose.eyeOpenness = 0.65
            pose.eyeOffset = -0.5
            pose.mouthCurve = 0.3
        }
        return pose
    }
}

/// What the artwork needs to draw its still pose.
struct TubeStatusContext: Equatable {
    var activity: AgentActivity = .unknown
    /// Present only while the short post-turn cue is current.
    var cue: AgentStatusCue?
}

private struct TubeStatusContextKey: EnvironmentKey {
    static let defaultValue = TubeStatusContext()
}

extension EnvironmentValues {
    var tubeStatusContext: TubeStatusContext {
        get { self[TubeStatusContextKey.self] }
        set { self[TubeStatusContextKey.self] = newValue }
    }
}

/// Draws one artwork piece in the current still pose.
struct TubeStatusReader<Content: View>: View {
    @ViewBuilder let content: (TubeStatusAppearance) -> Content
    @Environment(\.tubeStatusContext) private var context

    var body: some View {
        content(.make(activity: context.activity, cue: context.cue))
    }
}

/// Provides the shared status context to the glass, both rim halves, reflections and face.
struct TubeStatusPresentation<Content: View>: View {
    let snapshot: AgentStatusSnapshot
    let paused: Bool
    private let content: Content
    @State private var expiredCueID: String?

    init(snapshot: AgentStatusSnapshot, paused: Bool, @ViewBuilder content: () -> Content) {
        self.snapshot = snapshot
        self.paused = paused
        self.content = content()
    }

    var body: some View {
        content
            .environment(\.tubeStatusContext, context)
            .task(id: snapshot.cueID) { await expireCue() }
    }

    private var context: TubeStatusContext {
        TubeStatusContext(activity: snapshot.activity,
                          cue: !paused && hasCurrentCue ? snapshot.cue : nil)
    }

    private var hasCurrentCue: Bool {
        guard snapshot.cue != nil, let id = snapshot.cueID, id != expiredCueID,
              let date = snapshot.cueDate else { return false }
        let age = Date().timeIntervalSince(date)
        return age >= 0 && age < 3
    }

    private func expireCue() async {
        guard let id = snapshot.cueID, let date = snapshot.cueDate else { return }
        let remaining = max(0, 3 - Date().timeIntervalSince(date))
        do { try await Task.sleep(for: .seconds(remaining)) }
        catch { return }
        expiredCueID = id
    }
}
