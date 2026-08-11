import SwiftUI

/// The sidebar: a source list of the objects this app is actually about.
///
/// It used to list Home / Settings / Appearance — a web app's navigation inside
/// a Mac window. The objects here are cards, which is what every disk-oriented
/// Mac app puts in its source list, and it makes per-card folder assignment the
/// natural content of a selected row instead of something crammed into a
/// list item in the middle of the window.
struct CardSourceList: View {
    @ObservedObject var vm: ImportViewModel
    @Binding var selectedCard: String?

    /// Which card's custom-folder prompt is open, and for which media type.
    @State private var customPrompt: CustomFolderPrompt?
    @State private var customName: String = ""

    var body: some View {
        // The tag on each row must have the same type as the List's selection
        // *value* — String, not String?. Tagging with `String?.some(key)` made
        // every tag an Optional<String>, which matches nothing, so clicking a
        // row silently failed to select it and the per-card pickers below could
        // never appear. "All Cards" is nil to the rest of the app, so it travels
        // through the List as a sentinel and is unwrapped here.
        List(selection: Binding<String?>(
            get: { selectedCard ?? CardSourceList.allCardsSentinel },
            set: { selectedCard = $0 == CardSourceList.allCardsSentinel ? nil : $0 }
        )) {
            Section {
                allCardsRow

                ForEach(vm.removableVolumes, id: \.self) { url in
                    cardRow(for: url)
                }

                // Removing a card only hides it, so hiding has to be visibly
                // undoable. Without this the only clue that anything was removed
                // was the card no longer being there.
                if vm.hiddenCardCount > 0 {
                    Button {
                        vm.clearIgnoresAndRefresh()
                    } label: {
                        Label(
                            "Show \(vm.hiddenCardCount) removed card\(vm.hiddenCardCount == 1 ? "" : "s")",
                            systemImage: "arrow.uturn.backward"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help("Bring back cards you removed from this list")
                }
            } header: {
                HStack {
                    Text("Cards")
                    Spacer()
                    Button {
                        Task { await vm.addSourceVolume() }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    // Cards that macOS does not report as removable, network
                    // volumes, and card readers that mount oddly all need a
                    // manual way in. Losing this button made those unusable.
                    .iconOnlyLabel("Add a folder or volume as a source")
                }
            }

            if vm.removableVolumes.isEmpty {
                emptyState
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            destinationFooter
        }
        .alert(
            customPrompt.map { "New folder for \($0.mediaType.title.lowercased())" } ?? "",
            isPresented: Binding(
                get: { customPrompt != nil },
                set: { if !$0 { customPrompt = nil } }
            )
        ) {
            TextField("Folder name", text: $customName)
            Button("Set") { commitCustomName() }
            Button("Cancel", role: .cancel) { customPrompt = nil }
        } message: {
            Text("Files from this card land in this folder inside the destination. It is created during the import. Slashes are replaced with dashes.")
        }
    }

    // MARK: - Rows

    private var allCardsRow: some View {
        let count = vm.candidates.count
        return Label {
            HStack {
                Text("All Cards")
                Spacer()
                if count > 0 {
                    Text("\(count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: "square.grid.2x2")
        }
        .tag(CardSourceList.allCardsSentinel)
        .accessibilityLabel("All cards, \(count) files")
    }

    @ViewBuilder
    private func cardRow(for url: URL) -> some View {
        let key = vm.getVolumeRootPath(for: url) ?? url.path
        let files = vm.candidates(onCard: key)
        let isSelected = selectedCard == key

        VStack(alignment: .leading, spacing: Metrics.snug) {
            HStack(spacing: Metrics.snug) {
                Image(systemName: "sdcard")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 1) {
                    Text(url.lastPathComponent)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !files.isEmpty {
                        Text("\(files.count) files · \(vm.formatBytes(Double(files.reduce(0) { $0 + Int64($1.fileSize) })))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }

                Spacer()

                Button {
                    vm.removeVolumeFromList(for: url)
                } label: {
                    Image(systemName: "minus.circle")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                // The old glyph here was an eject symbol on a button that does
                // not eject — it drops the card from this list and forgets its
                // permission. Two different meanings of "eject" in one app.
                .iconOnlyLabel("Hide \(url.lastPathComponent) from this list. It does not eject the card, and Refresh brings it back.")
            }

            if let storage = vm.getStorageInfo(for: url) {
                StorageCapacityBar(
                    totalCapacity: storage.total,
                    availableCapacity: storage.available,
                    pendingCapacity: 0,
                    label: url.lastPathComponent
                )
            }

            // Folder routing is the app's differentiator, so it appears on the
            // card it belongs to — but only when that card is selected, so the
            // list stays scannable when several cards are mounted.
            if isSelected {
                Divider().padding(.vertical, 2)
                folderPicker(for: key, mediaType: .photos)
                folderPicker(for: key, mediaType: .videos)

                if vm.destinationFolders.isEmpty {
                    Text(destinationHint)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.vertical, Metrics.tight)
        .tag(key)
    }

    private func folderPicker(for key: String, mediaType: CardMediaType) -> some View {
        let current = mediaType.currentValue(vm: vm, key: key)
        let folders = vm.destinationFolders
        // An assignment whose folder is not on disk — typed through New Folder…,
        // or left behind by a different destination — still has to appear, or the
        // picker would silently show something other than what is stored.
        let isPending = current != CardSourceList.autoDetect && !folders.contains(current)

        return HStack(spacing: Metrics.snug) {
            Text(mediaType.title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            Picker(mediaType.title, selection: Binding(
                get: { current },
                set: { newValue in
                    if newValue == CardSourceList.customSentinel {
                        customName = ""
                        customPrompt = CustomFolderPrompt(key: key, mediaType: mediaType)
                    } else {
                        mediaType.apply(vm: vm, key: key, value: newValue)
                    }
                }
            )) {
                Text("Auto-detect").tag(CardSourceList.autoDetect)

                if isPending || !folders.isEmpty {
                    Divider()
                    if isPending {
                        Text("\(current) — not created yet").tag(current)
                    }
                    ForEach(folders, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                Divider()
                Text("New Folder…").tag(CardSourceList.customSentinel)
            }
            .labelsHidden()
            .controlSize(.small)
            .accessibilityLabel("\(mediaType.title) folder")
            .accessibilityValue(current)
            .help("Where \(mediaType.title.lowercased()) from this card are filed inside the destination")
        }
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: Metrics.tight) {
            Text("No cards detected")
                .foregroundStyle(.secondary)
            Text("Insert a camera card, or use Import ▸ Refresh Cards.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, Metrics.snug)
    }

    // MARK: - Destination

    private var destinationFooter: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: Metrics.snug) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 0) {
                    Text("Destination")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(vm.destinationURL?.lastPathComponent ?? "Not set")
                        .font(.caption)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(vm.destinationURL == nil ? Color.statusCaution : .primary)
                }

                Spacer()

                Button("Choose…") { vm.pickDestination() }
                    .controlSize(.small)
                    .help("Choose the destination folder (⇧⌘D)")
            }
            .padding(.horizontal, Metrics.regular)
            .padding(.vertical, Metrics.snug)
            .help(vm.destinationURL?.path ?? "No destination folder chosen yet")
        }
        .background(.bar)
    }

    // MARK: - Custom folder prompt

    private func commitCustomName() {
        guard let prompt = customPrompt else { return }
        let cleaned = ImportViewModel.sanitizeFolderName(customName)
        if !cleaned.isEmpty {
            prompt.mediaType.apply(vm: vm, key: prompt.key, value: cleaned)
        }
        customPrompt = nil
    }

    /// Why the pickers list real folders rather than a list kept in Settings:
    /// a typed name that matched nothing on disk looked identical to one that
    /// did, and the folder you actually wanted could only be reached by spelling
    /// it out exactly.
    private var destinationHint: String {
        guard let dest = vm.destinationURL else {
            return "Choose a destination to list its folders."
        }
        return "No folders in \(dest.lastPathComponent) yet. Use New Folder… to add one."
    }

    static let autoDetect = "Auto-Detect"
    static let customSentinel = "\u{0001}custom"
    static let allCardsSentinel = "\u{0001}all"

    struct CustomFolderPrompt: Identifiable {
        let key: String
        let mediaType: CardMediaType
        var id: String { "\(key)-\(mediaType.rawValue)" }
    }
}

/// Which stream of a card a folder assignment applies to. Stills and footage
/// from one physical card routinely belong in different places — that is the
/// point of the feature.
enum CardMediaType: String {
    case photos
    case videos

    var title: String { self == .photos ? "Photos" : "Videos" }

    func currentValue(vm: ImportViewModel, key: String) -> String {
        let stored = self == .photos ? vm.customBucketsPhotos[key] : vm.customBucketsVideos[key]
        return stored ?? CardSourceList.autoDetect
    }

    func apply(vm: ImportViewModel, key: String, value: String) {
        let url = URL(fileURLWithPath: key)
        if self == .photos {
            vm.setCustomPhotosBucket(for: url, bucket: value)
        } else {
            vm.setCustomVideosBucket(for: url, bucket: value)
        }
    }
}
