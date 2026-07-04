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
                        
                        Text("Tokens: {YYYY} {MM} {DD} {Camera} {OriginalName} {OriginalExtension}")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
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
}
