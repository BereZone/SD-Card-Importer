import SwiftUI

/// The primary action, and the only custom `ButtonStyle` in the app.
///
/// It exists for one reason the stock prominent style cannot cover: this button
/// changes identity mid-operation (Import becomes Cancel) and must read as
/// destructive in that state. Everything else about it is standard — no
/// gradient, no hover-scale, no shadow. The previous style animated scale on
/// hover and press with two springs, which is motion an ingest tool should not
/// have while it is moving someone's only copy of a shoot.
///
/// Crucially it draws a focus ring. The old custom styles drew none, so with
/// Full Keyboard Access enabled there was no visible focus anywhere on the
/// primary controls.
struct PrimaryActionButtonStyle: ButtonStyle {
    enum Role {
        case standard
        case destructive
    }

    var role: Role = .standard
    @Environment(\.isEnabled) private var isEnabled
    @FocusState private var isFocused: Bool

    private var fill: Color {
        switch role {
        case .standard:    return .brandAccent
        case .destructive: return .statusDanger
        }
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.body.weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, Metrics.gutter)
            .padding(.vertical, Metrics.snug)
            .background(
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .fill(fill.opacity(configuration.isPressed ? 0.8 : 1.0))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                    .strokeBorder(Color.brandAccent, lineWidth: isFocused ? 3 : 0)
                    .padding(-2)
            )
            .opacity(isEnabled ? 1.0 : 0.45)
            .contentShape(Rectangle())
            .focusable(isEnabled)
            .focused($isFocused)
    }
}

/// A count or state chip. Tinted background with a matching foreground, rather
/// than white text on a saturated fill — the old badge put white captions on the
/// system secondary grey whenever a count was zero, which was unreadable in
/// light appearance.
struct StatusChip: View {
    let text: String
    var severity: Severity = .info

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit())
            .foregroundStyle(severity == .info ? Color.secondary : severity.tint)
            .padding(.horizontal, Metrics.snug)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(
                    severity == .info
                        ? Color(nsColor: .quaternaryLabelColor)
                        : severity.tint.opacity(0.15)
                )
            )
    }
}

/// A section title inside a panel. Plain `.headline` — emphasis comes from
/// weight, which is what the platform does. The previous treatment filled every
/// heading with the same blue-to-purple gradient, so six unrelated headings were
/// typographically identical and nothing on screen was the subject.
struct SectionTitle: View {
    let text: String
    var symbol: String?

    var body: some View {
        Label {
            Text(text).font(.headline)
        } icon: {
            if let symbol {
                Image(systemName: symbol).foregroundStyle(.secondary)
            }
        }
        .labelStyle(.titleAndIcon)
        .accessibilityAddTraits(.isHeader)
    }
}

extension View {
    /// Attaches both the pointer tooltip and the VoiceOver name, because an
    /// icon-only control needs both and they are the same sentence. Eight
    /// icon-only controls previously had neither.
    func iconOnlyLabel(_ description: String) -> some View {
        self
            .help(description)
            .accessibilityLabel(description)
    }
}
