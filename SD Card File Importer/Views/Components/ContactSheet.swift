import SwiftUI
import QuickLook

enum ContactSheetLayout: String, CaseIterable, Identifiable {
    case grid
    case list
    case days

    var id: String { rawValue }

    var title: String {
        switch self {
        case .grid: return "Contact sheet"
        case .list: return "List"
        case .days: return "By day"
        }
    }

    var symbol: String {
        switch self {
        case .grid: return "square.grid.2x2"
        case .list: return "list.bullet"
        case .days: return "calendar"
        }
    }
}

/// The content area. This app is about photographs, and it previously displayed
/// them at 32 points with the size slider capped at 32 — the most
/// product-specific asset available, rendered at icon size. Here the contact
/// sheet leads and the thumbnail size slider does nothing but size thumbnails.
struct ContactSheet: View {
    @ObservedObject var vm: ImportViewModel
    let cardRoot: String?
    let layout: ContactSheetLayout

    @AppStorage("thumbnailSize") private var thumbnailSize: Double = 128
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true
    @State private var quickLookURL: URL?

    private var files: [ImportCandidate] {
        vm.candidates(onCard: cardRoot)
    }

    /// The files grouped by shoot day, newest day first. Shared by the Days
    /// layout and by Quick Look, so ← and → in the preview step through the
    /// files in the order they appear on screen.
    private var dayGroups: [(day: Date, items: [ImportCandidate])] {
        let groups = Dictionary(grouping: files) { candidate in
            Calendar.current.startOfDay(for: candidate.date)
        }
        return groups.keys.sorted(by: >).map { (day: $0, items: groups[$0] ?? []) }
    }

    /// Every URL on screen, in display order. Handing Quick Look the whole
    /// collection rather than one URL is what gives the panel its previous and
    /// next arrows and the ← → keys.
    private var displayedURLs: [URL] {
        switch layout {
        case .grid, .list:
            return files.map(\.url)
        case .days:
            return dayGroups.flatMap { $0.items.map(\.url) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if files.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .quickLookPreview($quickLookURL, in: displayedURLs)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: Metrics.regular) {
            Button("Select All") { vm.selectAll(onCard: cardRoot) }
                .disabled(files.isEmpty)
                .help("Select every file shown (⌘A)")

            Button("Select None") { vm.deselectAll(onCard: cardRoot) }
                .disabled(files.isEmpty)
                .help("Deselect every file shown (⇧⌘A)")

            Spacer()

            if !files.isEmpty {
                StatusChip(text: "\(selectedCount) of \(files.count) selected")
            }

            if layout != .list {
                Slider(value: $thumbnailSize, in: 72...320)
                    .frame(width: 110)
                    .controlSize(.small)
                    .accessibilityLabel("Thumbnail size")
                    .accessibilityValue("\(Int(thumbnailSize)) points")
                    .help("Thumbnail size")
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.snug)
        .background(.bar)
    }

    private var selectedCount: Int {
        files.filter { !vm.disabledCandidates.contains($0.id) }.count
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        ScrollView {
            switch layout {
            case .grid:
                gridBody(files)
            case .list:
                listBody(files)
            case .days:
                daysBody
            }
        }
        .scrollContentBackground(.hidden)
    }

    private func gridBody(_ items: [ImportCandidate]) -> some View {
        // Cells top-align, because thumbnails now differ in height: a portrait
        // frame is taller than a landscape one at the same long edge.
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: Metrics.regular, alignment: .top)],
            alignment: .leading,
            spacing: Metrics.regular
        ) {
            ForEach(items) { candidate in
                ContactSheetCell(
                    vm: vm,
                    candidate: candidate,
                    size: thumbnailSize,
                    showThumbnail: showThumbnails,
                    onPreview: { quickLookURL = candidate.url }
                )
            }
        }
        .padding(Metrics.gutter)
    }

    private func listBody(_ items: [ImportCandidate]) -> some View {
        LazyVStack(spacing: 0) {
            ForEach(items) { candidate in
                FileRow(
                    vm: vm,
                    candidate: candidate,
                    showThumbnail: showThumbnails,
                    onPreview: { quickLookURL = candidate.url }
                )
                Divider().padding(.leading, 52)
            }
        }
    }

    /// Grouping by shoot day is genuinely product-specific — it is how a
    /// photographer thinks about a card — so it survives the redesign as one of
    /// three views rather than one of four near-identical file browsers.
    private var daysBody: some View {
        LazyVStack(alignment: .leading, spacing: Metrics.section, pinnedViews: [.sectionHeaders]) {
            ForEach(dayGroups, id: \.day) { group in
                Section {
                    gridBody(group.items)
                } header: {
                    HStack {
                        Text(group.day.formatted(date: .complete, time: .omitted))
                            .font(.headline)
                        StatusChip(text: "\(group.items.count)")
                        Spacer()
                    }
                    .padding(.horizontal, Metrics.gutter)
                    .padding(.vertical, Metrics.snug)
                    .background(.bar)
                    .accessibilityAddTraits(.isHeader)
                }
            }
        }
    }

    // MARK: - Empty states

    /// Two genuinely different problems. They previously shared one headline —
    /// "Waiting for Media" — so a scanned card that yielded nothing told the
    /// user to insert a card they had already inserted.
    @ViewBuilder
    private var emptyState: some View {
        if vm.removableVolumes.isEmpty {
            EmptyStateView(
                symbol: "sdcard",
                title: "No card inserted",
                message: "Insert a camera card and its photos and videos will appear here automatically.",
                actionTitle: "Refresh Cards",
                action: { vm.refreshVolumes(autoScan: true) }
            )
        } else {
            EmptyStateView(
                symbol: "photo.on.rectangle.angled",
                title: "No importable files on this card",
                message: "The card is readable but holds no photos or videos matching your date filter. Camera proxy files such as LRV and THM are always skipped.",
                actionTitle: "Rescan",
                action: { vm.scanForCandidates() }
            )
        }
    }
}

/// One cell in the contact sheet.
struct ContactSheetCell: View {
    @ObservedObject var vm: ImportViewModel
    let candidate: ImportCandidate
    let size: CGFloat
    let showThumbnail: Bool
    let onPreview: () -> Void

    private var isSelected: Bool { !vm.disabledCandidates.contains(candidate.id) }
    private var isImported: Bool { vm.importedCandidateIDs.contains(candidate.id) }
    private var isFailed: Bool { vm.failedCandidateIDs.contains(candidate.id) }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.tight) {
            // The picture itself toggles the file — far easier to hit than
            // the small corner checkbox — and a real Button, so the toggle is
            // reachable by keyboard and by VoiceOver. Quick Look is its own
            // small button in the opposite corner. Both corner controls sit
            // outside the toggle button rather than inside its label — a
            // control nested in a button's label never receives its own
            // clicks, because the button swallows them.
            Button(action: { vm.toggleSelection(for: candidate) }) {
                ThumbnailView(url: candidate.url, size: size, show: showThumbnail)
                    .overlay {
                        RoundedRectangle(cornerRadius: Metrics.radiusControl, style: .continuous)
                            .strokeBorder(isSelected ? Color.brandAccent : .clear, lineWidth: 2)
                    }
                    .opacity(isSelected ? 1 : 0.5)
            }
            .buttonStyle(.plain)
            .help(isSelected ? "Click to skip this file" : "Click to import this file")
            .accessibilityLabel("Import \(candidate.url.lastPathComponent)")
            .accessibilityValue(isSelected ? "Selected" : "Skipped")
            .overlay(alignment: .topLeading) { selectionToggle }
            .overlay(alignment: .topTrailing) { quickLookButton }
            .overlay(alignment: .bottomTrailing) { outcomeBadge }

            Text(candidate.url.lastPathComponent)
                .font(.caption)
                .lineLimit(1)
                // Camera filenames differ at the end — DSC01234 vs DSC01235 —
                // so tail truncation hid the only distinguishing part.
                .truncationMode(.middle)
                .frame(maxWidth: size, alignment: .leading)

            if let destination = vm.previewDestinationFolder(for: candidate), !destination.isEmpty {
                Text(destination)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(maxWidth: size, alignment: .leading)
                    .help("Will be filed in \(destination)")
            }
        }
        .contextMenu {
            Button("Quick Look") { onPreview() }
            Button("Reveal on Card") {
                NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
            }
        }
    }

    private var selectionToggle: some View {
        Toggle(isOn: Binding(
            get: { isSelected },
            set: { _ in vm.toggleSelection(for: candidate) }
        )) {
            // The label is real, so VoiceOver names the file instead of saying
            // "checkbox" once per file. labelsHidden keeps the visual unchanged.
            Text("Import \(candidate.url.lastPathComponent)")
        }
        .toggleStyle(.checkbox)
        .labelsHidden()
        .padding(Metrics.tight)
        .background(.black.opacity(0.3), in: Circle())
        .padding(Metrics.tight)
    }

    private var quickLookButton: some View {
        QuickLookButton(name: candidate.url.lastPathComponent, onBackdrop: true, action: onPreview)
            .padding(Metrics.tight)
    }

    @ViewBuilder
    private var outcomeBadge: some View {
        if isFailed {
            badge(symbol: "xmark.octagon.fill", tint: .statusDanger, description: "Failed to import")
        } else if isImported {
            badge(symbol: "checkmark.circle.fill", tint: .statusSuccess, description: "Imported")
        }
    }

    private func badge(symbol: String, tint: Color, description: String) -> some View {
        Image(systemName: symbol)
            .foregroundStyle(.white, tint)
            .padding(Metrics.tight)
            .accessibilityLabel(description)
    }
}

/// A dense row, for when there are five thousand files and the filename matters
/// more than the picture.
struct FileRow: View {
    @ObservedObject var vm: ImportViewModel
    let candidate: ImportCandidate
    let showThumbnail: Bool
    let onPreview: () -> Void

    private var isSelected: Bool { !vm.disabledCandidates.contains(candidate.id) }

    var body: some View {
        HStack(spacing: Metrics.regular) {
            Toggle(isOn: Binding(
                get: { isSelected },
                set: { _ in vm.toggleSelection(for: candidate) }
            )) {
                Text("Import \(candidate.url.lastPathComponent)")
            }
            .toggleStyle(.checkbox)
            .labelsHidden()

            ThumbnailView(url: candidate.url, size: 28, show: showThumbnail, fixedSquare: true)

            VStack(alignment: .leading, spacing: 1) {
                Text(candidate.url.lastPathComponent)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if let destination = vm.previewDestinationFolder(for: candidate), !destination.isEmpty {
                    Text(destination)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            }

            Spacer()

            if vm.importedCandidateIDs.contains(candidate.id) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Color.statusSuccess)
                    .accessibilityLabel("Imported")
            } else if vm.failedCandidateIDs.contains(candidate.id) {
                Image(systemName: "xmark.octagon.fill")
                    .foregroundStyle(Color.statusDanger)
                    .accessibilityLabel("Failed")
            }

            Text(candidate.date.formatted(date: .abbreviated, time: .shortened))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            Text(vm.formatBytes(Double(candidate.fileSize)))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .trailing)

            QuickLookButton(name: candidate.url.lastPathComponent, action: onPreview)
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.snug)
        .opacity(isSelected ? 1 : 0.5)
        .contentShape(Rectangle())
        // The whole row toggles the file; the checkbox keeps the keyboard and
        // VoiceOver path to the same toggle, and the eye button is Quick Look.
        // A child control wins over this row gesture, so clicking either
        // control does not also toggle the row.
        .onTapGesture { vm.toggleSelection(for: candidate) }
        .contextMenu {
            Button("Quick Look") { onPreview() }
            Button("Reveal on Card") {
                NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
            }
        }
    }
}

/// The small eye that opens Quick Look on one file, shared by the grid cell
/// and the list row so the two views agree on the glyph and the tooltip.
struct QuickLookButton: View {
    let name: String
    /// Over a thumbnail the eye sits white on a dark circle, like the
    /// checkbox; on a plain list row it is a bare secondary glyph.
    var onBackdrop = false
    let action: () -> Void

    var body: some View {
        // The circle is part of the label, not a modifier on the button, so
        // the whole circle is the click target rather than just the glyph.
        Button(action: action) {
            Image(systemName: "eye")
                .font(.body.weight(.semibold))
                .foregroundStyle(onBackdrop ? Color.white : Color.secondary)
                .frame(width: 16, height: 16)
                .padding(onBackdrop ? Metrics.tight : 0)
                .background(.black.opacity(onBackdrop ? 0.3 : 0), in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help("Quick Look \(name)")
        .accessibilityLabel("Quick Look \(name)")
    }
}

/// One empty-state treatment, used with different words for different problems.
struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String?
    var action: (() -> Void)?

    var body: some View {
        VStack(spacing: Metrics.regular) {
            Image(systemName: symbol)
                .font(.system(size: 40))
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            Text(title)
                .font(.headline)

            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, Metrics.tight)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.section)
        .accessibilityElement(children: .contain)
    }
}
