import SwiftUI
import QuickLook

enum FileListLayout: String, CaseIterable, Identifiable {
    case list, grid, table, calendar
    var id: String { rawValue }
}
import QuickLook

struct FileListSection: View {
    @ObservedObject var vm: ImportViewModel
    @State private var previewURL: URL?
    @AppStorage("uiThumbnailSize") private var uiThumbnailSize: Double = 32.0
    @AppStorage("showPreviews") private var showPreviews: Bool = true
    @AppStorage("fileListLayout") private var layout: FileListLayout = .list
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(spacing: 12) {
                HStack {
                    Image(systemName: "doc.on.doc.fill")
                        .font(.title2)
                        .foregroundColor(.accentSecondary)
                    Text("Found Files")
                        .sectionHeader()
                        .layoutPriority(1)
                    
                    Spacer()
                    
                    StatusBadge(
                        text: "\(vm.selectedCandidatesCount)/\(vm.candidates.count) files",
                        color: vm.candidates.isEmpty ? .secondary : .successGreen
                    )
                    .layoutPriority(1)
                }
                
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
                            
                        Spacer()
                        
                        HStack(spacing: 16) {
                            Button(action: { layout = .list }) {
                                Image(systemName: "list.bullet")
                                    .foregroundColor(layout == .list ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { layout = .grid }) {
                                Image(systemName: "square.grid.2x2")
                                    .foregroundColor(layout == .grid ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { layout = .table }) {
                                Image(systemName: "tablecells")
                                    .foregroundColor(layout == .table ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                            
                            Button(action: { layout = .calendar }) {
                                Image(systemName: "calendar")
                                    .foregroundColor(layout == .calendar ? .accentColor : .secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.top, 4)
                    .padding(.bottom, 4)
                }
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
            PulsingEmptyIcon(systemName: "doc.text.magnifyingglass")
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
    }
    
    private let columns = [GridItem(.adaptive(minimum: 120, maximum: 200), spacing: 12)]
    
    private var filesList: some View {
        Group {
            switch layout {
            case .list:
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: CGFloat(10 - (32 - uiThumbnailSize)/3)) {
                        ForEach(vm.candidates) { c in
                            FileRow(candidate: c, vm: vm, previewURL: $previewURL)
                        }
                    }
                }
            case .grid:
                ScrollView {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(vm.candidates) { c in
                            FileGridItem(candidate: c, vm: vm, previewURL: $previewURL)
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 8)
                }
            case .table:
                tableLayout
            case .calendar:
                calendarLayout
            }
        }
        .frame(maxHeight: .infinity)
        .quickLookPreview($previewURL)
    }
    
    private var tableLayout: some View {
        Table(vm.candidates) {
            TableColumn("Import") { c in
                let isSelected = !vm.disabledCandidates.contains(c.id)
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in vm.toggleSelection(for: c) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
            }
            .width(50)
            
            TableColumn("Thumbnail") { c in
                ThumbnailView(url: c.url, size: 24, show: showPreviews)
                    .frame(width: 24, height: 24)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .width(60)
            
            TableColumn("Name") { c in
                Text(c.url.lastPathComponent)
                    .font(.system(.body, design: .rounded))
            }
            
            TableColumn("Size") { c in
                Text(byteCount(c.fileSize))
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(80)
            
            TableColumn("Date") { c in
                Text(c.date, style: .date)
                    .font(.system(.body, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .width(100)
            
            TableColumn("Type") { c in
                Text(c.url.pathExtension.uppercased())
                    .font(.system(.caption, design: .rounded).weight(.bold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
            .width(50)
        }
    }
    
    private var calendarLayout: some View {
        let grouped = Dictionary(grouping: vm.candidates) { c in
            Calendar.current.startOfDay(for: c.date)
        }
        let sortedDates = grouped.keys.sorted(by: >)
        
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(sortedDates, id: \.self) { date in
                    Section {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(grouped[date] ?? []) { c in
                                FileGridItem(candidate: c, vm: vm, previewURL: $previewURL)
                            }
                        }
                    } header: {
                        Text(date, format: .dateTime.month(.wide).day().year())
                            .font(.system(.title3, design: .rounded).weight(.bold))
                            .foregroundColor(.primary)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Capsule().fill(Color.cardBackgroundSecondary))
                            .padding(.top, 8)
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.bottom, 16)
        }
    }
    
    private func byteCount(_ n: UInt64) -> String {
        let f = ByteCountFormatter()
        f.allowedUnits = [.useMB, .useGB]
        f.countStyle = .file
        return f.string(fromByteCount: Int64(n))
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

struct FileGridItem: View {
    let candidate: ImportCandidate
    @ObservedObject var vm: ImportViewModel
    @Binding var previewURL: URL?
    @AppStorage("showPreviews") private var showPreviews: Bool = true
    
    var body: some View {
        let ext = candidate.url.pathExtension.lowercased()
        let isSelected = !vm.disabledCandidates.contains(candidate.id)
        
        VStack(spacing: 8) {
            ZStack(alignment: .topLeading) {
                ThumbnailView(url: candidate.url, size: 100, show: showPreviews)
                    .frame(maxWidth: .infinity, maxHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                    .onTapGesture {
                        previewURL = candidate.url
                    }
                
                Toggle("", isOn: Binding(
                    get: { isSelected },
                    set: { _ in vm.toggleSelection(for: candidate) }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                .padding(6)
            }
            
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(candidate.url.lastPathComponent)
                        .font(.system(.caption, design: .rounded))
                        .lineLimit(1)
                    Text(byteCount(candidate.fileSize))
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                Spacer()
                Text(ext.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.secondary.opacity(0.15)))
            }
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.accentPrimary.opacity(0.1) : Color.cardBackgroundSecondary)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.accentPrimary.opacity(0.5) : Color.clear, lineWidth: 1)
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
