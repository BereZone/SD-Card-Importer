import SwiftUI

struct OptionsCard: View {
    @Binding var options: ImportOptions
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .font(.title2)
                    .foregroundColor(.accentPrimary)
                Text("Import Options")
                    .sectionHeader()
            }
            
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "folder.fill")
                        .foregroundColor(.accentSecondary)
                    Text("Folder Structure")
                        .font(.system(.body, design: .rounded).weight(.medium))
                    Spacer()
                    Picker("", selection: $options.organizationMode) {
                        ForEach(ImportOptions.OrganizationMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 140)
                }
                .lineLimit(1)
                .lineLimit(1)
                
                Divider()
                
                HStack {
                    Image(systemName: "calendar")
                        .foregroundColor(.accentSecondary)
                    Text("Date Filter")
                        .font(.system(.body, design: .rounded).weight(.medium))
                    Spacer()
                    Picker("", selection: $options.dateFilter) {
                        ForEach(ImportOptions.DateFilter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 140)
                }
                .lineLimit(1)
                
                Divider()
                
                Toggle(isOn: $options.dryRun) {
                    HStack(spacing: 8) {
                        Image(systemName: options.dryRun ? "eye.fill" : "eye.slash.fill")
                            .foregroundColor(options.dryRun ? .accentPrimary : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Dry Run Mode")
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Text("Preview without copying files")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.accentPrimary)
                .lineLimit(1)
                
                Divider()
                
                Toggle(isOn: $options.moveInsteadOfCopy) {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.right.circle.fill")
                            .foregroundColor(options.moveInsteadOfCopy ? .warningOrange : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Move Instead of Copy")
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Text("⚠️ Removes files from SD card")
                                .font(.caption)
                                .foregroundColor(.warningOrange)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.warningOrange)
                .lineLimit(1)
                
                Divider()
                
                Toggle(isOn: $options.ejectAfterImport) {
                    HStack(spacing: 8) {
                        Image(systemName: "eject.circle.fill")
                            .foregroundColor(options.ejectAfterImport ? .successGreen : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Eject After Import")
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Text("Auto-eject SD cards when done")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.successGreen)
                .lineLimit(1)
                
                Divider()
                
                Toggle(isOn: $options.openDestinationWhenDone) {
                    HStack(spacing: 8) {
                        Image(systemName: "macwindow")
                            .foregroundColor(options.openDestinationWhenDone ? .accentPrimary : .secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Open After Import")
                                .font(.system(.body, design: .rounded).weight(.medium))
                            Text("Reveal in Destination Folder")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .toggleStyle(.switch)
                .tint(.accentPrimary)
                .lineLimit(1)
            }
            
            Spacer(minLength: 0)
        }
        .modernCard(accentColor: .accentPrimary)
    }
}
