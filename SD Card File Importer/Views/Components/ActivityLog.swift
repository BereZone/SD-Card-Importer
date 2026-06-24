import SwiftUI
#if os(macOS)
import AppKit
#endif

struct ActivityLogSection: View {
    @ObservedObject var vm: ImportViewModel
    @State private var logHeight: CGFloat = 120
    @State private var dragStartHeight: CGFloat = 120
    
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
                
                Button(action: { 
                    withAnimation { 
                        if logHeight <= 120 {
                            logHeight = 400
                            dragStartHeight = 400
                        } else {
                            logHeight = 120
                            dragStartHeight = 120
                        }
                    } 
                }) {
                    Image(systemName: logHeight <= 120 ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
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
                .frame(height: max(80, logHeight))
                .onChange(of: vm.logLines) { _, _ in
                    withAnimation {
                        proxy.scrollTo(max(0, vm.logLines.count - 1), anchor: .bottom)
                    }
                }
            }
            
            // Drag handle
            HStack {
                Spacer()
                Capsule()
                    .fill(Color.secondary.opacity(0.3))
                    .frame(width: 40, height: 4)
                Spacer()
            }
            .padding(.top, 4)
            .padding(.bottom, 2)
            .contentShape(Rectangle())
            .onHover { isHovering in
                if isHovering {
                    NSCursor.resizeUpDown.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture()
                    .onChanged { value in
                        let newHeight = dragStartHeight + value.translation.height
                        logHeight = max(80, newHeight)
                    }
                    .onEnded { value in
                        dragStartHeight = logHeight
                    }
            )
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
