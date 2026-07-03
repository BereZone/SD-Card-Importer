import SwiftUI

struct OptionsCard: View {
    @Binding var options: ImportOptions
    @AppStorage("uiThumbnailSize") private var uiThumbnailSize: Double = 32.0
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "gearshape.2.fill")
                    .font(.title2)
                    .foregroundColor(.accentPrimary)
                Text("Import Options")
                    .sectionHeader()
            }
            
            VStack(alignment: .leading, spacing: CGFloat(10 - (32 - uiThumbnailSize)/3)) {
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
                
                if options.dateFilter == .customRange {
                    HStack(spacing: 4) {
                        DatePicker("", selection: $options.customStartDate, displayedComponents: .date)
                            .labelsHidden()
                        Text("to")
                            .foregroundColor(.secondary)
                            .font(.system(.body, design: .rounded))
                        DatePicker("", selection: $options.customEndDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                    .padding(.leading, 32)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }
                
                Divider()
                
                Toggle(isOn: $options.renameFiles.animation()) {
                    HStack(spacing: 8) {
                        Image(systemName: "character.cursor.ibeam")
                            .foregroundColor(options.renameFiles ? .accentPrimary : .secondary)
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
                .lineLimit(1)
                
                if options.renameFiles {
                    VStack(alignment: .leading, spacing: 6) {
                        TextField("Template", text: $options.renameTemplate)
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
