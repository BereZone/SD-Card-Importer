import SwiftUI

@main
struct VideoImporterApp: App {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    
    var body: some Scene {
        WindowGroup {
            SidebarContentView()
                .preferredColorScheme(appTheme.colorScheme)
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
