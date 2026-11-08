import SwiftUI

/// Code-drawn glass: no bitmap background, no opaque rectangular app surface.
private struct VesselShape: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        return Path { p in
            p.move(to: CGPoint(x: 0, y: 0))
            p.addCurve(to: CGPoint(x: w, y: 0), control1: CGPoint(x: w * 0.22, y: 10), control2: CGPoint(x: w * 0.78, y: 10))
            p.addLine(to: CGPoint(x: w, y: h - 11))
            p.addCurve(to: CGPoint(x: w * 0.5, y: h), control1: CGPoint(x: w, y: h - 2), control2: CGPoint(x: w * 0.74, y: h))
            p.addCurve(to: CGPoint(x: 0, y: h - 11), control1: CGPoint(x: w * 0.26, y: h), control2: CGPoint(x: 0, y: h - 2))
            p.closeSubpath()
        }
    }
}

/// A crisp colored line with a soft halo, readable on light and dark desktops.
/// It is drawn once per status change; nothing animates.
private struct GlowOutline<S: Shape>: View {
    let shape: S
    let color: Color

    var body: some View {
        ZStack {
            shape.stroke(color.opacity(0.55), lineWidth: 6).blur(radius: 4)
            shape.stroke(color.opacity(0.9), lineWidth: 3).blur(radius: 1.5)
            shape.stroke(color, lineWidth: 1.6)
        }
    }
}

struct TubeBody: View {
    var body: some View {
        TubeStatusReader { TubeBodyArt(status: $0) }
    }
}

private struct TubeBodyArt: View {
    let status: TubeStatusAppearance

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                // Feet sit behind the rounded glass base, like the reference pet.
                HStack(spacing: TubeMetrics.footSpacing) {
                    foot.rotationEffect(.degrees(12))
                    foot.rotationEffect(.degrees(-12))
                }
                .position(x: geometry.size.width / 2, y: geometry.size.height - TubeMetrics.footBottom - TubeMetrics.footHeight / 2)
                VesselShape()
                    .fill(LinearGradient(colors: [StackTheme.glass.opacity(0.16), .white.opacity(0.035), StackTheme.lilac.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(VesselShape().stroke(LinearGradient(colors: [.white.opacity(0.94), StackTheme.blue.opacity(0.65), .white.opacity(0.9)], startPoint: .leading, endPoint: .trailing), lineWidth: 1.25))
                    .overlay { if let glow = status.glowColor { GlowOutline(shape: VesselShape(), color: glow) } }
                    .background(VesselShape().stroke(StackTheme.accent.opacity(0.18), lineWidth: 3).blur(radius: 2))
                    .padding(.horizontal, TubeMetrics.wallInset)
                    .padding(.top, TubeMetrics.mouthHeight / 2)
                    .padding(.bottom, 8)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var foot: some View {
        Ellipse()
            .fill(LinearGradient(colors: [StackTheme.lilac.opacity(0.9), StackTheme.accent.opacity(0.65)], startPoint: .top, endPoint: .bottom))
            .overlay(Ellipse().stroke(.white.opacity(0.7), lineWidth: 1))
            .frame(width: TubeMetrics.footWidth, height: TubeMetrics.footHeight)
    }
}

struct TubeRim: View {
    var body: some View {
        TubeStatusReader { TubeRimArt(status: $0) }
    }
}

private struct TubeRimArt: View {
    let status: TubeStatusAppearance

    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [StackTheme.blue.opacity(0.12), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom))
            Ellipse().stroke(StackTheme.accent.opacity(0.25), lineWidth: 3).blur(radius: 1)
            Ellipse().stroke(LinearGradient(colors: [.white.opacity(0.98), StackTheme.blue.opacity(0.9), .white.opacity(0.98)], startPoint: .top, endPoint: .bottom), lineWidth: 1.6)
            Ellipse().inset(by: 2.5).stroke(.white.opacity(0.75), lineWidth: 0.75)
            if let glow = status.glowColor { GlowOutline(shape: Ellipse(), color: glow) }
        }
        .padding(.horizontal, TubeMetrics.wallInset)
        .padding(.vertical, 2.5)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// Still reflections on the glass walls.
struct TubeFront: View {
    var body: some View {
        TubeStatusReader { TubeFrontArt(status: $0) }
    }
}

private struct TubeFrontArt: View {
    let status: TubeStatusAppearance

    var body: some View {
        GeometryReader { geometry in
            HStack {
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(status.reflectionStrength), .white.opacity(0.02), .white.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3)
                Spacer()
                Capsule()
                    .fill(LinearGradient(colors: [.white.opacity(0.2), .white.opacity(status.reflectionStrength * 0.6), StackTheme.blue.opacity(0.2)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 2)
            }
            .padding(.horizontal, TubeMetrics.wallInset + 3)
            .padding(.top, TubeMetrics.mouthHeight + 4)
            .padding(.bottom, 20)
            .overlay(alignment: .bottom) {
                Ellipse()
                    .stroke(LinearGradient(colors: [.clear, .white.opacity(0.85), .clear], startPoint: .leading, endPoint: .trailing), lineWidth: 1.5)
                    .frame(width: geometry.size.width - TubeMetrics.wallInset * 2 - 2, height: 15)
                    .padding(.bottom, 8.5)
            }
        }
        .clipped()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct TubeFace: View {
    var body: some View {
        TubeStatusReader { TubeFaceArt(status: $0) }
    }
}

private struct TubeFaceArt: View {
    let status: TubeStatusAppearance

    var body: some View {
        ZStack {
            Ellipse()
                .fill(LinearGradient(colors: [StackTheme.glass.opacity(0.02), StackTheme.lilac.opacity(0.18)], startPoint: .top, endPoint: .bottom))
                .frame(width: TubeMetrics.width - TubeMetrics.wallInset * 2 - 4, height: 21)
            HStack(spacing: 5.5) {
                cheek
                eye(mirrored: false)
                Mouth(curve: status.mouthCurve)
                    .stroke(StackTheme.ink, style: StrokeStyle(lineWidth: 1.25, lineCap: .round))
                    .frame(width: 7, height: 3.5)
                    .offset(y: 2.5)
                eye(mirrored: true)
                cheek
            }
            .offset(y: -2.5)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func eye(mirrored: Bool) -> some View {
        ZStack {
            if status.thinkingEyes {
                Ellipse()
                    .fill(.white.opacity(0.98))
                    .overlay(Ellipse().strokeBorder(StackTheme.ink.opacity(0.25), lineWidth: 0.6))
            }
            Ellipse()
                .fill(LinearGradient(colors: [StackTheme.ink, StackTheme.accent], startPoint: .top, endPoint: .bottom))
                .overlay(alignment: .topLeading) {
                    Circle().fill(.white)
                        .frame(width: status.thinkingEyes ? 2 : 1.5, height: status.thinkingEyes ? 2 : 1.5)
                        .offset(x: 1, y: 1)
                }
                .frame(width: status.thinkingEyes ? 7 : 5.5, height: status.thinkingEyes ? 8.5 : 7.5)
                .offset(x: status.eyeOffset, y: status.eyeVerticalOffset)
        }
        .frame(width: status.thinkingEyes ? 12 : 5.5, height: status.thinkingEyes ? 14 : 7.5)
        .scaleEffect(y: status.eyeOpenness)
        .overlay(alignment: .top) {
            Capsule().fill(StackTheme.ink)
                .frame(width: 7, height: 1)
                .rotationEffect(.degrees(mirrored ? -status.browAngle : status.browAngle))
                .offset(y: -3)
                .opacity(status.showsBrows ? 1 : 0)
        }
    }

    private var cheek: some View {
        Ellipse().fill(StackTheme.pink.opacity(0.8))
            .frame(width: 7.5, height: 3).blur(radius: 0.5).offset(y: 4.5)
    }

    private struct Mouth: Shape {
        var curve: CGFloat

        var animatableData: CGFloat {
            get { curve }
            set { curve = newValue }
        }

        func path(in rect: CGRect) -> Path {
            Path { path in
                path.move(to: CGPoint(x: 0, y: 0))
                path.addQuadCurve(to: CGPoint(x: rect.width, y: 0),
                                  control: CGPoint(x: rect.midX, y: rect.height * 1.7 * curve))
            }
        }
    }
}
