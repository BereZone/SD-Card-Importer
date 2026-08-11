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

/// The nested folder tree, showing the template's shape rather than a single
/// slash-separated line — a folder structure is easier to read as a folder
/// structure.
///
/// The difference from the original is where the values come from. That version
/// printed `SONY_A7IV / 2026 / 10_October / A7IV_001.ARW` unconditionally, no
/// matter which card was inserted or what today's date was, so it agreed with
/// reality only by coincidence. This one resolves through the same
/// `buildDestination` the import itself uses whenever a card is present, and
/// falls back to clearly-labelled example values when there is nothing to
/// resolve.
struct DestinationPreview: View {
    @ObservedObject var vm: ImportViewModel

    /// Folder segments and the leaf filenames to show beneath them.
    private var tree: (segments: [String], leaves: [(String, String)], isReal: Bool) {
        if let sample = vm.candidates.first,
           let resolved = vm.previewDestination(for: sample) {
            let parts = resolved.split(separator: "/").map(String.init)
            let folders = Array(parts.dropLast())
            var leaves: [(String, String)] = []
            if let photo = vm.candidates.first(where: { !MediaTypes.isVideoExtension($0.url) }),
               let name = vm.previewDestination(for: photo)?.split(separator: "/").last {
                leaves.append(("photo", String(name)))
            }
            if let video = vm.candidates.first(where: { MediaTypes.isVideoExtension($0.url) }),
               let name = vm.previewDestination(for: video)?.split(separator: "/").last {
                leaves.append(("video", String(name)))
            }
            if leaves.isEmpty, let name = parts.last {
                leaves.append(("photo", name))
            }
            return (folders, leaves, true)
        }

        let segments = vm.options.folderTemplate
            .components(separatedBy: "/")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map(Self.exampleValue)
        return (segments, [("photo", "IMG_0001.RAW"), ("video", "IMG_0002.MOV")], false)
    }

    var body: some View {
        let tree = tree

        VStack(alignment: .leading, spacing: Metrics.snug) {
            HStack(spacing: Metrics.tight) {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
                Text(vm.destinationURL?.lastPathComponent ?? "Destination")
                    .font(.callout.weight(.medium))
            }

            FolderTreeLevel(segments: tree.segments, index: 0, leaves: tree.leaves)
                .padding(.leading, Metrics.regular)

            Text(tree.isReal
                 ? "Resolved from the card currently inserted."
                 : "Example values — insert a card to see real paths.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Destination preview: \(tree.segments.joined(separator: ", then "))")
    }

    /// Only ever used when no card is inserted, and labelled as an example
    /// wherever it appears.
    static func exampleValue(for token: String) -> String {
        let now = Date()
        let calendar = Calendar.current
        var s = token
        s = s.replacingOccurrences(of: "{YYYY}", with: String(calendar.component(.year, from: now)))
        s = s.replacingOccurrences(of: "{MM}", with: String(format: "%02d", calendar.component(.month, from: now)))
        s = s.replacingOccurrences(of: "{DD}", with: String(format: "%02d", calendar.component(.day, from: now)))
        s = s.replacingOccurrences(of: "{Camera}", with: "Camera")
        s = s.replacingOccurrences(of: "{OriginalName}", with: "IMG_0001")
        s = s.replacingOccurrences(of: "{OriginalExtension}", with: "RAW")
        return s
    }
}

/// One level of the nested tree, recursing into the next.
struct FolderTreeLevel: View {
    let segments: [String]
    let index: Int
    let leaves: [(String, String)]

    var body: some View {
        if index < segments.count {
            VStack(alignment: .leading, spacing: Metrics.tight) {
                node(icon: "folder.fill", text: segments[index], isFolder: true)
                FolderTreeLevel(segments: segments, index: index + 1, leaves: leaves)
                    .padding(.leading, Metrics.gutter)
            }
        } else {
            VStack(alignment: .leading, spacing: Metrics.tight) {
                ForEach(leaves, id: \.1) { kind, name in
                    node(icon: kind == "video" ? "video" : "photo", text: name, isFolder: false)
                }
            }
        }
    }

    private func node(icon: String, text: String, isFolder: Bool) -> some View {
        HStack(spacing: Metrics.tight) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(isFolder ? Color.brandAccent : .secondary)
            Text(text)
                .font(.caption.monospaced())
                .lineLimit(1)
                .truncationMode(.middle)
        }
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
