import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ActivityLogSection: View {
    @ObservedObject var vm: ImportViewModel
    @AppStorage("uiThumbnailSize") private var uiThumbnailSize: Double = 32.0
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
                    LazyVStack(alignment: .leading, spacing: CGFloat(3 - (32 - uiThumbnailSize)/6)) {
                        // `LogEntry` carries its own stable id, so this no longer
                        // materializes an enumerated copy of the whole log on every
                        // append, and trimming old lines doesn't renumber the rest.
                        ForEach(vm.logLines) { entry in
                            logLineView(entry: entry)
                        }
                    }
                }
                .frame(maxHeight: .infinity)
                // Watching the count rather than the array avoids an O(n) element-wise
                // comparison per appended line, which made a long import O(n²).
                .onChange(of: vm.logLines.count) { _, _ in
                    guard let lastID = vm.logLines.last?.id else { return }
                    withAnimation {
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }
        }
        .modernCard(accentColor: .accentPrimary)
    }

    private func logLineView(entry: LogEntry) -> some View {
        let line = entry.text
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
        
        return HStack(spacing: CGFloat(8 - (32 - uiThumbnailSize)/3)) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundColor(color)
                .frame(width: 12)
            
            Text(line)
                .font(.system(uiThumbnailSize < 28 ? .caption2 : .caption, design: .monospaced))
                .foregroundColor(.primary)
        }
        .id(entry.id)
        .padding(.vertical, CGFloat(2 - (32 - uiThumbnailSize)/6))
    }
}
