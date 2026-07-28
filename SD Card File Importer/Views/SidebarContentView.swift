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
    
    /// Read straight from the bundle so it can never drift from what shipped:
    /// `MARKETING_VERSION` in the Xcode project feeds `CFBundleShortVersionString`.
    /// The build number is deliberately left out — `CURRENT_PROJECT_VERSION` never
    /// increments, so it would show a constant "(1)" and tell nobody anything.
    private var versionLabel: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
        return "v\(version ?? "—")"
    }

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
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
                .listStyle(.sidebar)
                .scrollContentBackground(windowTranslucency ? .automatic : .hidden)

                Divider()

                // Selectable so it can be copied straight into a bug report.
                HStack {
                    Text(versionLabel)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .help("SD Card File Importer \(versionLabel)")
                    Spacer()
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 6)
            }
            .navigationTitle("SD Importer")
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
