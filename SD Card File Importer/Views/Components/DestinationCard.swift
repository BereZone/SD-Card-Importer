import SwiftUI

struct DestinationCard: View {
    @ObservedObject var vm: ImportViewModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "folder.fill.badge.gearshape")
                    .font(.body)
                    .foregroundColor(.accentPrimary)
                Text("Import Destination")
                    .sectionHeader()
                Spacer()
            }
            
            HStack(spacing: 12) {
                Image(systemName: vm.destinationURL == nil ? "folder.badge.questionmark" : "folder.fill")
                    .font(.title)
                    .foregroundColor(vm.destinationURL == nil ? .warningOrange : .successGreen)
                    .frame(width: 40, height: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    if let dest = vm.destinationURL {
                        Text(dest.lastPathComponent)
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .lineLimit(1)
                        Text(dest.path(percentEncoded: false))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    } else {
                        Text("No destination selected")
                            .font(.system(.headline, design: .rounded).weight(.semibold))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                        Text("Choose a folder to import files")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                
                Spacer()
                
                Button {
                    vm.pickDestination()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "folder.badge.plus")
                        Text("Choose")
                            .lineLimit(1)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            
            if let storage = vm.destinationStorage {
                Divider()
                    .padding(.vertical, 4)
                
                StorageCapacityBar(
                    totalCapacity: storage.total,
                    availableCapacity: storage.available,
                    pendingCapacity: vm.pendingImportSize
                )
            }
            
            Spacer(minLength: 0)
        }
        .modernCard(accentColor: .accentPrimary)
    }
}
