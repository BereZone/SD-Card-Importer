import SwiftUI

@main
struct VideoImporterApp: App {
    var body: some Scene {
        WindowGroup {
            ImporterView()
        }
        .windowStyle(.titleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
    }
}
