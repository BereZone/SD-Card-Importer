import SwiftUI

struct ImporterView: View {
    @StateObject private var vm = ImportViewModel()
    
    var body: some View {
        ZStack {
            // Subtle gradient background
            LinearGradient(
                colors: [
                    Color(NSColor.windowBackgroundColor),
                    Color(NSColor.windowBackgroundColor).opacity(0.95)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    appHeader
                    DestinationCard(vm: vm)
                    SDCardsSection(vm: vm)
                    OptionsCard(options: $vm.options)
                    actionButtons
                    FileListSection(vm: vm)
                    ActivityLogSection(vm: vm)
                }
                .padding(16)
            }
        }
        .frame(minWidth: 700, minHeight: 600)
    }
    
    private var appHeader: some View {
        HStack {
            Image(systemName: "square.and.arrow.down.on.square.fill")
                .font(.system(size: 24))
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentPrimary, .accentSecondary],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
            VStack(alignment: .leading, spacing: 1) {
                Text("SD Import")
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Text("Organize your media files automatically")
                    .font(.system(.caption, design: .rounded))
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
    }
    
    private var actionButtons: some View {
        HStack(spacing: 16) {
            Button {
                withAnimation {
                    vm.scanForCandidates()
                }
            } label: {
                Label("Scan SD Cards", systemImage: "magnifyingglass.circle.fill")
            }
            .buttonStyle(SecondaryButtonStyle())
            
            Button {
                Task {
                    await vm.importAll()
                }
            } label: {
                Label("Start Import", systemImage: "square.and.arrow.down.fill")
            }
            .buttonStyle(PremiumButtonStyle(color: .successGreen))
            .disabled(vm.destinationURL == nil || vm.isImporting)
            .opacity((vm.destinationURL == nil || vm.isImporting) ? 0.5 : 1.0)
            
            Spacer()
            
            if vm.isImporting || vm.progress > 0 {
                HStack(spacing: 8) {
                    ProgressView(value: vm.progress)
                        .progressViewStyle(.linear)
                        .tint(.accentPrimary)
                        .frame(width: 180)
                    Text("\(Int(vm.progress * 100))%")
                        .font(.system(.caption, design: .rounded).weight(.semibold))
                        .foregroundColor(.accentPrimary)
                        .frame(width: 40)
                }
            }
        }
        .padding(.vertical, 4)
    }
}
