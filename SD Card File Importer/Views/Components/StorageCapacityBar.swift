import SwiftUI

/// Used / pending / free, as three bands.
///
/// This is the one piece of the old interface that was genuinely authored for
/// this product, so its behaviour survives the redesign intact: unticking files
/// makes the pending band retreat, which turns "will this fit?" into direct
/// manipulation instead of an error after the fact. What changed is that it no
/// longer carries its most important state in colour alone, and it now has an
/// accessible value — a bar that says nothing to VoiceOver does not exist for
/// some of its users.
struct StorageCapacityBar: View {
    let totalCapacity: Int64
    let availableCapacity: Int64
    let pendingCapacity: Int64
    var label: String = "Storage"

    private var usedCapacity: Int64 { max(0, totalCapacity - availableCapacity) }
    private var isOverCapacity: Bool { pendingCapacity > availableCapacity }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.tight) {
            GeometryReader { geo in
                let width = geo.size.width
                let safeTotal = totalCapacity > 0 ? Double(totalCapacity) : 1.0
                let usedRatio = min(1.0, max(0, Double(usedCapacity) / safeTotal))
                let pendingRatio = min(1.0 - usedRatio, max(0, Double(pendingCapacity) / safeTotal))

                ZStack(alignment: .leading) {
                    Capsule().fill(Color(nsColor: .quaternaryLabelColor))

                    Capsule()
                        .fill(Color.secondary)
                        .frame(width: max(width * usedRatio, usedCapacity > 0 ? 4 : 0))

                    if pendingCapacity > 0 {
                        Capsule()
                            .fill(isOverCapacity ? Color.statusDanger : Color.brandAccent)
                            .frame(width: max(width * pendingRatio, 4))
                            .offset(x: width * usedRatio)
                    }
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())

            HStack(spacing: Metrics.tight) {
                Text("\(format(usedCapacity)) used")
                    .foregroundStyle(.secondary)

                if pendingCapacity > 0 {
                    Text("· \(format(pendingCapacity)) selected")
                        .foregroundStyle(isOverCapacity ? Color.statusDanger : Color.brandAccent)
                }

                Spacer()

                // Over-capacity is red *and* says so in words. Colour alone would
                // leave the most consequential state on this bar invisible to a
                // colour-blind user.
                Text(isOverCapacity
                     ? "Not enough space"
                     : "\(format(max(0, availableCapacity - pendingCapacity))) free")
                    .foregroundStyle(isOverCapacity ? Color.statusDanger : .secondary)
                    .fontWeight(isOverCapacity ? .semibold : .regular)
            }
            .font(.caption2.monospacedDigit())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) capacity")
        .accessibilityValue(accessibilityDescription)
    }

    private var accessibilityDescription: String {
        var text = "\(format(usedCapacity)) used of \(format(totalCapacity)), \(format(availableCapacity)) free"
        if pendingCapacity > 0 {
            text += ", \(format(pendingCapacity)) selected for import"
            if isOverCapacity { text += ". Not enough space" }
        }
        return text
    }

    private func format(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
