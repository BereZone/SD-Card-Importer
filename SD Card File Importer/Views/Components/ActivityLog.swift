import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ActivityLogSection: View {
    @ObservedObject var vm: ImportViewModel
    @AppStorage("uiDensity") private var uiDensity: UIDensity = .comfortable
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Image(systemName: "terminal.fill")
                    .font(.title2)
                    .foregroundColor(.accentPrimary)
                Text("Activity Log")
                    .sectionHeader()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Spacer()
                if !vm.logLines.isEmpty {
                    StatusBadge(
                        text: "\(vm.logLines.count) event\(vm.logLines.count == 1 ? "" : "s")",
                        color: .accentPrimary
                    )
                }
            }
            
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: uiDensity == .compact ? 1 : 3) {
                        ForEach(Array(vm.logLines.enumerated()), id: \.offset) { i, line in
                            logLineView(line: line, index: i)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
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
        
        return HStack(spacing: uiDensity == .compact ? 4 : 8) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 12)
            
            Text(line)
                .font(.system(uiDensity == .compact ? .caption2 : .caption, design: .monospaced))
                .foregroundColor(.primary)
        }
        .id(index)
        .padding(.vertical, uiDensity == .compact ? 0 : 2)
    }
}
