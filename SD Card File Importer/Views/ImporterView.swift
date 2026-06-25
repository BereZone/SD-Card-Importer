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
            
            HSplitView {
                // Left Column: Controls
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        appHeader
                        
                        HStack(spacing: 16) {
                            DestinationCard(vm: vm)
                                .frame(maxHeight: .infinity)
                            SDCardsSection(vm: vm)
                                .frame(maxHeight: .infinity)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                        
                        HStack(spacing: 16) {
                            OptionsCard(options: $vm.options)
                                .frame(maxHeight: .infinity)
                            actionCard
                                .frame(maxHeight: .infinity)
                        }
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(16)
                    .minimumScaleFactor(0.85)
                }
                .frame(minWidth: 450)
                .layoutPriority(1)
                
                // Middle Column: Found Files
                FileListSection(vm: vm)
                    .padding(16)
                    .frame(minWidth: 250)
                
                // Right Column: Activity Log
                ActivityLogSection(vm: vm)
                    .padding(16)
                    .frame(minWidth: 250)
            }
        }
        .frame(minWidth: 1000, minHeight: 650)
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
    
    private var actionCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "play.circle.fill")
                    .font(.title2)
                    .foregroundColor(.accentPrimary)
                Text("Actions")
                    .sectionHeader()
            }
            
            VStack(spacing: 16) {
                Button {
                    withAnimation {
                        vm.scanForCandidates()
                    }
                } label: {
                    Label("Scan SD Cards", systemImage: "magnifyingglass.circle.fill")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .buttonStyle(SecondaryButtonStyle())
                
                Button {
                    Task {
                        await vm.importAll()
                    }
                } label: {
                    Label("Start Import", systemImage: "square.and.arrow.down.fill")
                        .frame(maxWidth: .infinity)
                        .lineLimit(1)
                }
                .buttonStyle(PremiumButtonStyle(color: .successGreen))
                .disabled(vm.destinationURL == nil || vm.isImporting)
                .opacity((vm.destinationURL == nil || vm.isImporting) ? 0.5 : 1.0)
                
                if vm.isImporting || vm.progress > 0 {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Progress")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                            Text("\(Int(vm.progress * 100))%")
                                .font(.caption.weight(.bold))
                                .foregroundColor(.accentPrimary)
                        }
                        ProgressView(value: vm.progress)
                            .progressViewStyle(.linear)
                            .tint(.accentPrimary)
                    }
                }
                
                Spacer(minLength: 0)
            }
        }
        .modernCard(accentColor: .accentPrimary)
    }
}
