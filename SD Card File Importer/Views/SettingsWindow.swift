import SwiftUI

/// The Settings scene, reached with ⌘, like every other Mac app.
///
/// Settings and Appearance used to be rows in the main window's sidebar, so ⌘,
/// did nothing and configuration competed for space with the task.
struct SettingsWindow: View {
    @ObservedObject var vm: ImportViewModel

    var body: some View {
        TabView {
            OrganizationSettings(vm: vm)
                .tabItem { Label("Organization", systemImage: "folder") }

            FolderNameSettings(vm: vm)
                .tabItem { Label("Folder Names", systemImage: "tag") }

            AppearanceSettings()
                .tabItem { Label("Appearance", systemImage: "paintpalette") }
        }
        .frame(width: 520, height: 420)
    }
}

// MARK: - Organization

struct OrganizationSettings: View {
    @ObservedObject var vm: ImportViewModel

    private static let folderTokens = ["{Camera}", "{YYYY}", "{MM}", "{DD}", "/"]
    private static let nameTokens = ["{YYYY}", "{MM}", "{DD}", "{Camera}", "{OriginalName}", "{OriginalExtension}"]

    var body: some View {
        Form {
            Section {
                TextField("Folder template", text: $vm.options.folderTemplate)
                    .font(.body.monospaced())
                TokenRow(tokens: Self.folderTokens, target: $vm.options.folderTemplate)
            } header: {
                Text("Folders")
            } footer: {
                Text("How imported files are grouped inside the destination.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Toggle("Rename files on import", isOn: $vm.options.renameFiles)

                if vm.options.renameFiles {
                    TextField("Name template", text: $vm.options.renameTemplate)
                        .font(.body.monospaced())
                    TokenRow(tokens: Self.nameTokens, target: $vm.options.renameTemplate)
                }
            } header: {
                Text("File Names")
            }

            Section {
                DestinationPreview(vm: vm)
            } header: {
                Text("Preview")
            }
        }
        .formStyle(.grouped)
    }
}

/// Token buttons that insert at the end of the template.
struct TokenRow: View {
    let tokens: [String]
    @Binding var target: String

    var body: some View {
        HStack(spacing: Metrics.tight) {
            ForEach(tokens, id: \.self) { token in
                Button(token) { target += token }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .font(.caption.monospaced())
                    .help("Insert \(token)")
            }
            Spacer()
            Button("Clear") { target = "" }
                .controlSize(.small)
                .disabled(target.isEmpty)
        }
    }
}

/// Resolves the template against a real file from a real card whenever one is
/// present. The old preview was hardcoded fiction — it printed
/// `SONY_A7IV / 2026 / 10_October` no matter which card was inserted or what the
/// date was, in a tab far away from the import.
struct DestinationPreview: View {
    @ObservedObject var vm: ImportViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.tight) {
            if let sample = vm.candidates.first,
               let resolved = vm.previewDestination(for: sample) {
                Label {
                    Text(resolved)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                } icon: {
                    Image(systemName: "arrow.turn.down.right").foregroundStyle(.secondary)
                }
                Text("Resolved from \(sample.url.lastPathComponent) on the inserted card.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if vm.destinationURL == nil {
                Text("Choose a destination folder to see where files will land.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("Insert a card to preview a real path.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Folder names

struct FolderNameSettings: View {
    @ObservedObject var vm: ImportViewModel
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.regular) {
            Text("Folder names offered when assigning a card's photos or videos.")
                .font(.callout)
                .foregroundStyle(.secondary)

            List {
                ForEach(vm.dropdownBuckets, id: \.self) { name in
                    HStack {
                        Image(systemName: "folder").foregroundStyle(.secondary)
                        Text(name)
                        Spacer()
                        Button(role: .destructive) {
                            vm.dropdownBuckets.removeAll { $0 == name }
                            vm.saveDropdownBuckets()
                        } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.plain)
                        .iconOnlyLabel("Remove \(name)")
                    }
                }
                .onMove { source, destination in
                    vm.dropdownBuckets.move(fromOffsets: source, toOffset: destination)
                    vm.saveDropdownBuckets()
                }
            }
            .frame(minHeight: 200)

            HStack {
                TextField("New folder name", text: $newName)
                    .onSubmit(add)
                Button("Add", action: add)
                    .disabled(ImportViewModel.sanitizeFolderName(newName).isEmpty)
            }
        }
        .padding(Metrics.section)
    }

    private func add() {
        let clean = ImportViewModel.sanitizeFolderName(newName)
        guard !clean.isEmpty, !vm.dropdownBuckets.contains(clean) else { return }
        vm.dropdownBuckets.append(clean)
        vm.saveDropdownBuckets()
        newName = ""
    }
}

// MARK: - Appearance

struct AppearanceSettings: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("showThumbnails") private var showThumbnails: Bool = true

    var body: some View {
        Form {
            Section {
                Picker("Appearance", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.inline)
            }

            Section {
                Toggle("Show thumbnails", isOn: $showThumbnails)
                Text("Turning thumbnails off makes very large cards list faster.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("Contact Sheet")
            }
        }
        .formStyle(.grouped)
    }
}
