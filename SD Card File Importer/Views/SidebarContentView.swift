import SwiftUI

enum SidebarTab: Hashable {
    case home
    case appearance
}

struct SidebarContentView: View {
    @State private var selectedTab: SidebarTab? = .home
    
    var body: some View {
        NavigationSplitView {
            List(selection: $selectedTab) {
                NavigationLink(value: SidebarTab.home) {
                    Label("Home", systemImage: "house.fill")
                }
                
                NavigationLink(value: SidebarTab.appearance) {
                    Label("Appearance", systemImage: "paintbrush.fill")
                }
            }
            .navigationTitle("SD Importer")
            .listStyle(.sidebar)
        } detail: {
            switch selectedTab {
            case .home:
                ImporterView()
            case .appearance:
                AppearanceView()
            case .none:
                Text("Select an item from the sidebar")
                    .foregroundColor(.secondary)
            }
        }
    }
}
