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
                    HStack {
                        DatePicker("", selection: $options.customStartDate, displayedComponents: .date)
                            .labelsHidden()
                            .frame(width: 110, alignment: .center)
                        
                        Spacer()
                        
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        DatePicker("", selection: $options.customEndDate, displayedComponents: .date)
                            .labelsHidden()
                            .frame(width: 110, alignment: .center)
                    }
                    .padding(8)
                    .background(Color.secondary.opacity(0.05))
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.secondary.opacity(0.1), lineWidth: 1)
                    )
                    .padding(.leading, 28)
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
