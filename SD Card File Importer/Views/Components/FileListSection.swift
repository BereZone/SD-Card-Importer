import SwiftUI
import QuickLook

struct FileListSection: View {
    @ObservedObject var vm: ImportViewModel
    @State private var previewURL: URL?
    
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
                
                Button(action: { vm.showPreviews.toggle() }) {
                    Image(systemName: vm.showPreviews ? "eye.fill" : "eye.slash.fill")
                        .foregroundColor(.secondary)
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .help("Toggle Previews")
                
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
        VStack(spacing: 4) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 28))
                .foregroundColor(.secondary.opacity(0.5))
            Text("No files found")
                .font(.system(.subheadline, design: .rounded).weight(.medium))
                .foregroundColor(.secondary)
            Text("Click 'Scan SD Cards' to find files")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
    }
    
    private var filesList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
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
    
    var body: some View {
        let ext = candidate.url.pathExtension.lowercased()
        
        return HStack(spacing: 10) {
            Toggle("", isOn: Binding(
                get: { !vm.disabledCandidates.contains(candidate.id) },
                set: { _ in vm.toggleSelection(for: candidate) }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            
            
            HStack(spacing: 10) {
                ThumbnailView(url: candidate.url, size: 32, show: vm.showPreviews)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.url.lastPathComponent)
                        .font(.system(.body, design: .rounded))
                        .lineLimit(1)
                    Text(byteCount(candidate.fileSize))
                        .font(.system(.caption, design: .monospaced))
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
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
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
