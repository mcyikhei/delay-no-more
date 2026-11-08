import SwiftUI
import DelayCore

/// Native palette: colored task tiles stay opaque enough for readable names;
/// the vessel uses these colors only at low opacity so the desktop shows through.
enum StackTheme {
    static let accent = Color(hex: 0x6553B4)
    static let ink = Color(hex: 0x403456)
    static let pink = Color(hex: 0xFFC7F0)
    static let lemon = Color(hex: 0xFFE4AE)
    static let mint = Color(hex: 0x97EBDF)
    static let blue = Color(hex: 0xB3CAFF)
    static let lilac = Color(hex: 0xE4C1FB)
    static let glass = Color(hex: 0xDCEEFF)
    static let codexWorking = Color(hex: 0x38B6FF)
    static let codexFailed = Color(hex: 0xF07474)
    static let codexWaiting = Color(hex: 0xF3D25C)
    static let codexFinished = Color(hex: 0x75D8AB)
    static let water = Color(hex: 0x4CC9E0)
    static let cardRadius: CGFloat = 8

    static func cardFill(_ color: CardColor) -> Color {
        switch color {
        case .pink: return pink
        case .lemon: return lemon
        case .mint: return mint
        case .blue: return blue
        case .lilac: return lilac
        }
    }

    static func motion(reduced: Bool) -> Animation? {
        reduced ? nil : .spring(response: 0.38, dampingFraction: 0.67)
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xff) / 255,
                  green: Double((hex >> 8) & 0xff) / 255,
                  blue: Double(hex & 0xff) / 255,
                  opacity: 1)
    }
}

/// Shared point geometry for artwork, SwiftUI content and native hit routing.
enum TubeMetrics {
    static let width: CGFloat = 104
    static let height: CGFloat = 208
    static let draftHeadroom: CGFloat = 35
    static let wallInset: CGFloat = 9
    static let cardInset: CGFloat = 13
    static let cardTopInset: CGFloat = 6
    static let mouthHeight: CGFloat = 20
    static let baseHeight: CGFloat = 28
    static let cardHeight: CGFloat = 30
    static let cardSpacing: CGFloat = 5
    static let footWidth: CGFloat = 12
    static let footHeight: CGFloat = 9
    static let footSpacing: CGFloat = 36
    static let footBottom: CGFloat = 3

    static func uprightPanelFrame(for artwork: CGRect) -> CGRect {
        CGRect(x: artwork.minX, y: artwork.minY,
               width: artwork.width, height: artwork.height + draftHeadroom)
    }

    static func uprightArtworkArea(in visible: CGRect) -> CGRect {
        CGRect(x: visible.minX, y: visible.minY,
               width: visible.width, height: max(1, visible.height - draftHeadroom))
    }
}
