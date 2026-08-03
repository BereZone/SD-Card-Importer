import SwiftUI
import AppKit

/// Semantic colour roles.
///
/// There is deliberately no brand palette here. This app is a utility that sits
/// beside Lightroom while the user looks at photographs; a saturated identity of
/// its own would compete with the only content that matters. It previously
/// hardcoded five sRGB values that were identical in light and dark, ignored the
/// user's system accent, and ignored Increase Contrast — while also using the
/// real system accent for the same jobs, so two different blues appeared on one
/// screen.
///
/// Everything below resolves through AppKit, so appearance, accent choice and
/// accessibility settings are honoured for free.
extension Color {
    /// Selection, progress, and the primary action. This is the user's accent,
    /// not ours.
    static var brandAccent: Color { .accentColor }

    /// Ground behind the window's content.
    static var surfaceBackground: Color { Color(nsColor: .windowBackgroundColor) }

    /// Raised surfaces: panels, the plan bar, contact-sheet cells.
    static var surfaceRaised: Color { Color(nsColor: .controlBackgroundColor) }

    /// Hairlines between structural regions.
    static var surfaceSeparator: Color { Color(nsColor: .separatorColor) }

    /// Destructive operations and over-capacity. One red, used for both.
    static var statusDanger: Color { .red }

    /// Completed and verified.
    static var statusSuccess: Color { .green }

    /// Skipped, renamed, or otherwise worth noticing without being wrong.
    static var statusCaution: Color { .orange }
}

/// How an event or outcome should be presented. Severity used to be encoded as
/// an emoji prefix inside the log string and recovered by substring-matching
/// that emoji, which meant VoiceOver read "white heavy check mark" aloud and
/// any message that happened to contain the character was miscategorised.
enum Severity: String, Codable, Hashable {
    case info
    case success
    case caution
    case failure

    var tint: Color {
        switch self {
        case .info:    return .secondary
        case .success: return .statusSuccess
        case .caution: return .statusCaution
        case .failure: return .statusDanger
        }
    }

    var symbol: String {
        switch self {
        case .info:    return "info.circle"
        case .success: return "checkmark.circle.fill"
        case .caution: return "exclamationmark.triangle.fill"
        case .failure: return "xmark.octagon.fill"
        }
    }

    /// Spoken by VoiceOver in place of the icon, so severity survives without
    /// sight and without punctuation being read as words.
    var accessibilityDescription: String {
        switch self {
        case .info:    return "Information"
        case .success: return "Succeeded"
        case .caution: return "Warning"
        case .failure: return "Failed"
        }
    }
}
