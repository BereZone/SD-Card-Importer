import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: ImportViewModel
    @State private var newBucketName: String = ""
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentPrimary, .accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Settings")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Configure core application behavior")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Organization")
                    .sectionHeader()
                
                VStack(alignment: .leading, spacing: 6) {
                    TextField("Template", text: $vm.options.folderTemplate)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentPrimary.opacity(0.1))
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.accentPrimary.opacity(0.3), lineWidth: 1)
                        )
                    
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Insert Token:")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        HStack(spacing: 8) {
                            folderTokenButton("{Camera}")
                            folderTokenButton("{YYYY}")
                            folderTokenButton("{MM}")
                            folderTokenButton("{DD}")
                        }
                        
                        HStack(spacing: 8) {
                            folderTokenButton("/")
                            
                            Button(action: {
                                vm.options.folderTemplate = ""
                            }) {
                                Text("Clear")
                                    .font(.caption)
                                    .foregroundColor(.red)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color.red.opacity(0.1))
                                    .cornerRadius(6)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.vertical, 4)
                
                Text("Determines how imported files are grouped into folders at the destination.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                FolderPreviewView(template: vm.options.folderTemplate)
                    .padding(.top, 4)
            }
            .modernCard(accentColor: .accentPrimary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Naming Templates")
                    .sectionHeader()
                
                Toggle(isOn: $vm.options.renameFiles.animation()) {
                    HStack(spacing: 8) {
                        Image(systemName: "character.cursor.ibeam")
                            .foregroundColor(vm.options.renameFiles ? .accentPrimary : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Rename Files")
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Text("Apply custom naming template")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.accentPrimary)
                
                if vm.options.renameFiles {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Template", text: $vm.options.renameTemplate)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(Color.accentPrimary.opacity(0.1))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.accentPrimary.opacity(0.3), lineWidth: 1)
                            )
                        
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Insert Token:")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 8) {
                                tokenButton("{YYYY}")
                                tokenButton("{MM}")
                                tokenButton("{DD}")
                                tokenButton("{Camera}")
                            }
                            
                            HStack(spacing: 8) {
                                tokenButton("{OriginalName}")
                                tokenButton("{OriginalExtension}")
                                
                                Button(action: {
                                    vm.options.renameTemplate = ""
                                }) {
                                    Text("Clear")
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.red.opacity(0.1))
                                        .cornerRadius(6)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.leading, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
            .modernCard(accentColor: .accentSecondary)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Bucket Dropdown Options")
                    .sectionHeader()
                
                Text("Manage the pre-defined folder names that appear in the SD Card list dropdown.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                VStack(spacing: 8) {
                    ForEach(vm.dropdownBuckets, id: \.self) { bucket in
                        if bucket != "Auto-Detect" && bucket != "Custom..." {
                            HStack {
                                Text(bucket)
                                    .font(.system(.body, design: .rounded))
                                Spacer()
                                Button(action: {
                                    vm.dropdownBuckets.removeAll(where: { $0 == bucket })
                                    vm.saveDropdownBuckets()
                                }) {
                                    Image(systemName: "trash.fill")
                                        .foregroundColor(.red.opacity(0.8))
                                }
                                .buttonStyle(.plain)
                            }
                            .padding(.vertical, 4)
                            .padding(.horizontal, 12)
                            .background(Color.cardBackgroundSecondary)
                            .cornerRadius(6)
                        }
                    }
                }
                
                HStack {
                    TextField("New bucket name", text: $newBucketName)
                        .textFieldStyle(.plain)
                        .font(.system(.body, design: .rounded))
                        .padding(8)
                        .background(
                            RoundedRectangle(cornerRadius: 6)
                                .fill(Color.accentPrimary.opacity(0.1))
                        )
                    
                    Button(action: {
                        let trimmed = newBucketName.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !trimmed.isEmpty && !vm.dropdownBuckets.contains(trimmed) {
                            // Insert before Custom... if it exists
                            if let customIndex = vm.dropdownBuckets.firstIndex(of: "Custom...") {
                                vm.dropdownBuckets.insert(trimmed, at: customIndex)
                            } else {
                                vm.dropdownBuckets.append(trimmed)
                            }
                            vm.saveDropdownBuckets()
                            newBucketName = ""
                        }
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(.accentPrimary)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 4)
            }
            .modernCard(accentColor: .accentPrimary)
            
            Spacer()
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 400, minHeight: 400, alignment: .topLeading)
    }
    private func folderTokenButton(_ token: String) -> some View {
        Button(action: {
            vm.options.folderTemplate += token
        }) {
            Text(token)
                .font(.caption.monospaced())
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
    
    private func tokenButton(_ token: String) -> some View {
        Button(action: {
            vm.options.renameTemplate += token
        }) {
            Text(token)
                .font(.caption.monospaced())
                .foregroundColor(.accentColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.accentColor.opacity(0.1))
                .cornerRadius(6)
        }
        .buttonStyle(.plain)
    }
}

struct FolderPreviewView: View {
    let template: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentSecondary)
                    .font(.system(size: 12))
                Text("Destination")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            
            let segments = template
                .components(separatedBy: "/")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            
            DynamicFolderTree(segments: segments, index: 0)
                .padding(.leading, 12)
                .padding(.top, 2)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.accentPrimary.opacity(0.05))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.accentPrimary.opacity(0.15), lineWidth: 1)
        )
    }
}

struct DynamicFolderTree: View {
    let segments: [String]
    let index: Int
    
    var body: some View {
        if index < segments.count {
            VStack(alignment: .leading, spacing: 4) {
                let seg = mockValue(for: segments[index])
                treeNode(icon: "folder.fill", text: seg)
                
                DynamicFolderTree(segments: segments, index: index + 1)
                    .padding(.leading, 14)
            }
        } else {
            VStack(alignment: .leading, spacing: 4) {
                treeNode(icon: "photo.fill", text: "A7IV_001.ARW")
                treeNode(icon: "video.fill", text: "A7IV_002.MP4")
            }
            .padding(.top, 2)
        }
    }
    
    private func mockValue(for token: String) -> String {
        var s = token
        s = s.replacingOccurrences(of: "{YYYY}", with: "2026")
        s = s.replacingOccurrences(of: "{MM}", with: "10_October")
        s = s.replacingOccurrences(of: "{DD}", with: "24")
        s = s.replacingOccurrences(of: "{Camera}", with: "SONY_A7IV")
        return s
    }
    
    private func treeNode(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundColor(icon == "folder.fill" ? .accentSecondary : .secondary)
                .font(.system(size: 11))
            Text(text)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.primary)
        }
    }
}
