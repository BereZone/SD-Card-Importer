import SwiftUI

struct ActivityLogSection: View {
    @ObservedObject var vm: ImportViewModel
    @State private var isExpanded: Bool = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.accentPrimary)
                Text("Activity Log")
                    .sectionHeader()
                Spacer()
                if !vm.logLines.isEmpty {
                    StatusBadge(
                        text: "\(vm.logLines.count) event\(vm.logLines.count == 1 ? "" : "s")",
                        color: .accentPrimary
                    )
                }
                
                Button(action: { withAnimation { isExpanded.toggle() } }) {
                    Image(systemName: isExpanded ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(Array(vm.logLines.enumerated()), id: \.offset) { i, line in
                            logLineView(line: line, index: i)
                        }
                    }
                }
                .frame(minHeight: 80, maxHeight: isExpanded ? 400 : 120)
                .onChange(of: vm.logLines) { _, _ in
                    withAnimation {
                        proxy.scrollTo(max(0, vm.logLines.count - 1), anchor: .bottom)
                    }
                }
            }
        }
        .modernCard(accentColor: .accentPrimary)
    }

    private func logLineView(line: String, index: Int) -> some View {
        let icon: String
        let color: Color
        if line.contains("✅") {
            icon = "checkmark.circle.fill"
            color = .successGreen
        } else if line.contains("❌") || line.contains("❗️") {
            icon = "xmark.circle.fill"
            color = .errorRed
        } else if line.contains("⚠️") {
            icon = "exclamationmark.triangle.fill"
            color = .warningOrange
        } else {
            icon = "info.circle.fill"
            color = .accentPrimary
        }
        
        return HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 12)
            
            Text(line)
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.primary)
        }
        .id(index)
        .padding(.vertical, 2)
    }
}
