import SwiftUI

/// The spacing scale. Before this existed the view layer used fifteen distinct
/// padding and spacing magnitudes with no relationship between them; every
/// literal below replaces a family of near-identical numbers.
///
/// Tight within a group, generous between groups. Anything that needs a value
/// not on this scale is either a mistake or a genuine one-off that should say
/// why in a comment.
enum Metrics {
    /// Inside a single label group — icon to its text, value to its unit.
    static let tight: CGFloat = 4
    /// Between related controls in the same row or stack.
    static let snug: CGFloat = 8
    /// Default spacing between controls.
    static let regular: CGFloat = 12
    /// Window and pane insets.
    static let gutter: CGFloat = 16
    /// Between distinct groups that should read as separate.
    static let section: CGFloat = 20

    /// Controls, thumbnails, badges.
    static let radiusControl: CGFloat = 6
    /// Raised panels.
    static let radiusPanel: CGFloat = 10

    /// Smallest comfortable pointer target. Below this, precision suffers on a
    /// trackpad, which is how most of this app's users are driving it.
    static let hitTarget: CGFloat = 28

    /// The window has to fit a 13" laptop beside another window — that is the
    /// field scene, and it is the constraining one. The previous 1000×650
    /// minimum did not.
    static let windowMinWidth: CGFloat = 820
    static let windowMinHeight: CGFloat = 520
}

extension View {
    /// A raised, opaque panel. Opaque matters: the old card fill was a
    /// translucent control colour over a translucent window gradient, which
    /// left cards with almost no edge in dark mode and made a 1px coloured
    /// stroke the only thing separating them from the ground.
    func panel(padding: CGFloat = Metrics.regular) -> some View {
        self
            .padding(padding)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusPanel, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1)
            )
    }
}
