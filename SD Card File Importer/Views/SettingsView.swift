import SwiftUI

struct SettingsView: View {
    @ObservedObject var vm: ImportViewModel
    
    var body: some View {
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
                
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentSecondary)
                    Text("Folder Structure")
                        .font(.system(.body, design: .rounded).weight(.medium))
                    Spacer()
                    Picker("", selection: $vm.options.organizationMode) {
                        ForEach(ImportOptions.OrganizationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 160)
                }
                
                Text("Determines how imported files are grouped into folders at the destination.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    
                FolderPreviewView(mode: vm.options.organizationMode)
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
            
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 400, alignment: .topLeading)
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
    let mode: ImportOptions.OrganizationMode
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .foregroundColor(.accentSecondary)
                    .font(.system(size: 12))
                Text("Destination")
                    .font(.system(.caption, design: .rounded).weight(.semibold))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                if mode == .cameraFirst {
                    cameraFirstTree
                } else {
                    dateFirstTree
                }
            }
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
    
    private var cameraFirstTree: some View {
        VStack(alignment: .leading, spacing: 4) {
            treeNode(icon: "folder.fill", text: "SONY_A7IV")
            VStack(alignment: .leading, spacing: 4) {
                treeNode(icon: "folder.fill", text: "2026")
                VStack(alignment: .leading, spacing: 4) {
                    treeNode(icon: "folder.fill", text: "10_October")
                    VStack(alignment: .leading, spacing: 4) {
                        treeNode(icon: "folder.fill", text: "24")
                        VStack(alignment: .leading, spacing: 4) {
                            treeNode(icon: "photo.fill", text: "A7IV_001.ARW")
                            treeNode(icon: "video.fill", text: "A7IV_002.MP4")
                        }
                        .padding(.leading, 14)
                    }
                    .padding(.leading, 14)
                }
                .padding(.leading, 14)
            }
            .padding(.leading, 14)
        }
    }
    
    private var dateFirstTree: some View {
        VStack(alignment: .leading, spacing: 4) {
            treeNode(icon: "folder.fill", text: "2026")
            VStack(alignment: .leading, spacing: 4) {
                treeNode(icon: "folder.fill", text: "10_October")
                VStack(alignment: .leading, spacing: 4) {
                    treeNode(icon: "folder.fill", text: "24")
                    VStack(alignment: .leading, spacing: 4) {
                        treeNode(icon: "folder.fill", text: "SONY_A7IV")
                        VStack(alignment: .leading, spacing: 4) {
                            treeNode(icon: "photo.fill", text: "A7IV_001.ARW")
                            treeNode(icon: "video.fill", text: "A7IV_002.MP4")
                        }
                        .padding(.leading, 14)
                    }
                    .padding(.leading, 14)
                }
                .padding(.leading, 14)
            }
            .padding(.leading, 14)
        }
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
