import SwiftUI

struct StorageCapacityBar: View {
    let totalCapacity: Int64
    let availableCapacity: Int64
    let pendingCapacity: Int64
    
    var usedCapacity: Int64 {
        totalCapacity - availableCapacity
    }
    
    var isOverCapacity: Bool {
        pendingCapacity > availableCapacity
    }
    
    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                let width = geo.size.width
                
                let safeTotal = totalCapacity > 0 ? Double(totalCapacity) : 1.0
                let usedRatio = min(1.0, max(0, Double(usedCapacity) / safeTotal))
                let pendingRatio = min(1.0 - usedRatio, max(0, Double(pendingCapacity) / safeTotal))
                
                let usedWidth = width * usedRatio
                let pendingWidth = width * pendingRatio
                
                ZStack(alignment: .leading) {
                    // Background (Free Space)
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    
                    // Used Space
                    Capsule()
                        .fill(Color.secondary.opacity(0.5))
                        .frame(width: usedWidth > 0 ? max(usedWidth, 8) : 0)
                        
                    // Pending Space
                    if pendingCapacity > 0 {
                        Capsule()
                            .fill(isOverCapacity ? Color.red : Color.accentPrimary)
                            .frame(width: pendingWidth > 0 ? max(pendingWidth, 8) : 0)
                            .offset(x: usedWidth)
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            
            HStack {
                Text("\(formatBytes(usedCapacity)) Used")
                    .foregroundColor(.secondary)
                Spacer()
                if pendingCapacity > 0 {
                    Text("+\(formatBytes(pendingCapacity))")
                        .foregroundColor(isOverCapacity ? .red : .accentPrimary)
                        .fontWeight(isOverCapacity ? .bold : .semibold)
                    Spacer()
                }
                Text("\(formatBytes(max(0, availableCapacity - pendingCapacity))) Free")
                    .foregroundColor(isOverCapacity ? .red : .secondary)
            }
            .font(.system(size: 10, weight: .medium, design: .rounded))
        }
    }
    
    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useGB, .useMB, .useTB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: max(0, bytes))
    }
}
