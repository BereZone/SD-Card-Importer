import SwiftUI
import QuickLook

struct FileListSection: View {
    @ObservedObject var vm: ImportViewModel
    @State private var previewURL: URL?
    @AppStorage("uiThumbnailSize") private var uiThumbnailSize: Double = 32.0
    @AppStorage("showPreviews") private var showPreviews: Bool = true
    @State private var isPulsing = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "doc.on.doc.fill")
                    .font(.title2)
                    .foregroundColor(.accentSecondary)
                Text("Found Files")
                    .sectionHeader()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                
                Spacer()
                
                if !vm.candidates.isEmpty {
                    HStack(spacing: 12) {
                        Button("All") { vm.selectAll() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.accentColor)
                        
                        Button("None") { vm.deselectAll() }
                            .font(.caption)
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                    }
                    .padding(.trailing, 8)
                }
                
                StatusBadge(
                    text: "\(vm.selectedCandidatesCount)/\(vm.candidates.count) files",
                    color: vm.candidates.isEmpty ? .secondary : .successGreen
                )
            }
            
            if vm.candidates.isEmpty {
                emptyFilesView
            } else {
                filesList
            }
        }
        .modernCard(accentColor: .accentSecondary)
    }
    
    private var emptyFilesView: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(Color.accentSecondary.opacity(0.1))
                    .frame(width: 80, height: 80)
                    .scaleEffect(isPulsing ? 1.2 : 0.8)
                    .opacity(isPulsing ? 0 : 1)
                    .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: isPulsing)
                
                Circle()
                    .fill(Color.accentSecondary.opacity(0.1))
                    .frame(width: 60, height: 60)
                
                Image(systemName: "doc.text.magnifyingglass")
                    .font(.system(size: 28, weight: .light))
                    .foregroundColor(.accentSecondary)
            }
            .padding(.top, 10)
            
            VStack(spacing: 4) {
                Text("Waiting for Media")
                    .font(.system(.headline, design: .rounded).weight(.semibold))
                    .foregroundColor(.primary)
                Text("Insert an SD card to find files")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 30)
        .onAppear { isPulsing = true }
    }
    
    private var filesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: CGFloat(10 - (32 - uiThumbnailSize)/3)) {
                ForEach(vm.candidates) { c in
                    FileRow(candidate: c, vm: vm, previewURL: $previewURL)
                }
            }
        }
        .frame(maxHeight: .infinity)
        .quickLookPreview($previewURL)
    }
}

struct FileRow: View {
    let candidate: ImportCandidate
    @ObservedObject var vm: ImportViewModel
    @Binding var previewURL: URL?
    @AppStorage("uiThumbnailSize") private var uiThumbnailSize: Double = 32.0
    @AppStorage("showPreviews") private var showPreviews: Bool = true
    
    var body: some View {
        let ext = candidate.url.pathExtension.lowercased()
        
        return HStack(spacing: CGFloat(10 - (32 - uiThumbnailSize)/3)) {
            Toggle("", isOn: Binding(
                get: { !vm.disabledCandidates.contains(candidate.id) },
                set: { _ in vm.toggleSelection(for: candidate) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            
            
            HStack(spacing: CGFloat(10 - (32 - uiThumbnailSize)/3)) {
                ThumbnailView(url: candidate.url, size: CGFloat(uiThumbnailSize), show: showPreviews)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.url.lastPathComponent)
                        .font(.system(uiThumbnailSize < 28 ? .caption : .body, design: .rounded))
                        .lineLimit(1)
                    Text(byteCount(candidate.fileSize))
                        .font(.system(uiThumbnailSize < 28 ? .caption2 : .caption, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Text(ext.uppercased())
                    .font(.system(.caption2, design: .rounded).weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
            .contentShape(Rectangle())
            .onTapGesture {
                previewURL = candidate.url
            }
        }
        .padding(.horizontal, CGFloat(8 - (32 - uiThumbnailSize)/3))
        .padding(.vertical, CGFloat(6 - (32 - uiThumbnailSize)/3))
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.cardBackgroundSecondary)
        )
        .contextMenu {
            Button("View in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
            }
        }
    }
    
    private func byteCount(_ n: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
    }
}
