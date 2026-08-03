import SwiftUI

@main
@MainActor
struct SDCardFileImporterApp: App {
    /// Owned here rather than in a view, because the Settings scene and the main
    /// window are separate scenes that must share one model. Settings used to be
    /// a row in the sidebar, which is why it could get away with living inside
    /// the window's view tree.
    @StateObject private var vm = ImportViewModel()
    @AppStorage("appTheme") private var appTheme: AppTheme = .system

    var body: some Scene {
        // One name for the app. The bundle, the window, the sidebar and an
        // in-window header previously disagreed four different ways.
        WindowGroup("SD Card File Importer") {
            ImporterView(vm: vm)
                .preferredColorScheme(appTheme.colorScheme)
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1080, height: 680)
        .commands { ImporterCommands(vm: vm) }

        // ⌘, now does what it does in every other Mac app.
        Settings {
            SettingsWindow(vm: vm)
                .preferredColorScheme(appTheme.colorScheme)
        }
    }
}

/// Menu commands. The app previously declared exactly one command — removing
/// New Item — and shipped zero keyboard shortcuts, so nothing in the primary
/// flow could be driven from the keyboard.
struct ImporterCommands: Commands {
    @ObservedObject var vm: ImportViewModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) { }

        CommandMenu("Import") {
            Button("Refresh Cards") { vm.clearIgnoresAndRefresh() }
                .keyboardShortcut("r", modifiers: .command)

            Button("Add Source Folder…") { Task { await vm.addSourceVolume() } }
                .keyboardShortcut("o", modifiers: .command)

            Button("Rescan Files") { vm.scanForCandidates() }
                .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Button("Select All Files") { vm.selectAll() }
                .keyboardShortcut("a", modifiers: .command)

            Button("Deselect All Files") { vm.deselectAll() }
                .keyboardShortcut("a", modifiers: [.command, .shift])

            Divider()

            // Routed through requestImport so the keyboard path cannot skip the
            // confirmation that the button path enforces.
            Button(vm.options.dryRun ? "Start Preview" : "Start Import") {
                vm.requestImport()
            }
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(!vm.canStartImport)

            // ⌘. is the Mac convention for stopping an operation in progress.
            Button("Cancel Import") { vm.cancelImport() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(!vm.isImporting || vm.isCancelling)

            Divider()

            Button("Choose Destination…") { vm.pickDestination() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
    }
}
