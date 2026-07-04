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
            
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 400, alignment: .topLeading)
    }
}
