import SwiftUI

/// A status light for checksum verification.
///
/// Verification is the product's central promise and it is a per-run setting, so
/// whether it is armed should be readable at a glance rather than by opening a
/// popover. Lit means every copy is being re-read and compared to its source;
/// unlit means it is not.
///
/// It is an indicator, not a control — it reports state and never swallows a
/// click. The label is always present, so the state does not live in colour
/// alone.
struct VerificationIndicator: View {
    /// Verification will run for this import.
    let isOn: Bool
    /// Forced on because a Move is selected and an original is never deleted
    /// unverified.
    let isLocked: Bool
    /// An import is running right now.
    let isActive: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var pulsing = false

    private var tint: Color { isOn ? .statusSuccess : Color(nsColor: .quaternaryLabelColor) }

    var body: some View {
        HStack(spacing: Metrics.tight) {
            ZStack {
                // The halo only appears while verification is actually doing
                // something, so a lit-but-idle light never looks like activity.
                Circle()
                    .fill(tint.opacity(0.35))
                    .frame(width: 14, height: 14)
                    .scaleEffect(pulsing ? 1.0 : 0.6)
                    .opacity(isOn && isActive ? 1 : 0)

                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
                    .overlay(Circle().strokeBorder(.black.opacity(0.15), lineWidth: 0.5))
            }
            .frame(width: 14, height: 14)

            Text(isOn ? "Verifying" : "Not verifying")
                .font(.caption)
                .foregroundStyle(isOn ? Color.statusSuccess : .secondary)

            if isLocked {
                Image(systemName: "lock.fill")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { startPulseIfNeeded() }
        .onChange(of: isActive) { startPulseIfNeeded() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Checksum verification")
        .accessibilityValue(accessibilityValue)
        .help(helpText)
    }

    private func startPulseIfNeeded() {
        guard isOn, isActive, !reduceMotion else {
            pulsing = false
            return
        }
        withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) {
            pulsing = true
        }
    }

    private var accessibilityValue: String {
        if !isOn { return "Off. Copies will not be checked against the originals." }
        if isLocked { return "On and locked, because moving files always verifies before deleting an original." }
        return isActive ? "On, verifying now." : "On."
    }

    private var helpText: String {
        if isLocked { return "Always on when moving files — an original is never deleted unverified" }
        return isOn
            ? "Each copy is re-read and compared to the original"
            : "Copies are not checked against the originals"
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
