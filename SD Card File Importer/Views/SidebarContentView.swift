import SwiftUI

enum SidebarTab: Hashable {
    case home
    case settings
    case appearance
}

@MainActor
struct SidebarContentView: View {
    @StateObject private var vm = ImportViewModel()
    @State private var selectedTab: SidebarTab? = .home
    @AppStorage("windowTranslucency") private var windowTranslucency: Bool = true
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: SidebarTab.home) {
                    Label("Home", systemImage: "house.fill")
                }
                
                NavigationLink(value: SidebarTab.settings) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                
                NavigationLink(value: SidebarTab.appearance) {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }
            }
            .navigationTitle("SD Importer")
            .listStyle(.sidebar)
            .scrollContentBackground(windowTranslucency ? .automatic : .hidden)
            .background(windowTranslucency ? Color.clear : Color(NSColor.controlBackgroundColor))
        } detail: {
            Group {
                switch selectedTab {
            case .home:
                ImporterView(vm: vm)
            case .settings:
                SettingsView(vm: vm)
            case .appearance:
                AppearanceView()
            case .none:
                Text("Select item from the sidebar")
                    .foregroundColor(.secondary)
            }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(windowTranslucency ? Color.clear : Color(NSColor.windowBackgroundColor))
        }
    }
}
