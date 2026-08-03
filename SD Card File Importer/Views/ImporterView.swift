import SwiftUI

/// The main window.
///
/// THESIS: a contact sheet with a stated plan underneath it. The previous
/// arrangement was a 2×2 grid of equal-weight cards — Destination, Cards,
/// Options, "Actions" — in which the primary button occupied one quadrant and
/// nothing on screen was the subject. In an ingest tool exactly two things
/// matter: what you are about to move, and where it is going. Everything else is
/// configuration, and configuration belongs in a toolbar, a popover, or Settings.
///
/// Three bands: toolbar, split content, plan bar.
struct ImporterView: View {
    @ObservedObject var vm: ImportViewModel

    /// `nil` means "all cards". The source list drives this, and the contact
    /// sheet filters on it.
    @State private var selectedCard: String?
    @State private var layout: ContactSheetLayout = .grid
    @State private var showOptions = false
    @State private var showHistory = false

    var body: some View {
        NavigationSplitView {
            CardSourceList(vm: vm, selectedCard: $selectedCard)
                .navigationSplitViewColumnWidth(min: 200, ideal: 240, max: 320)
        } detail: {
            VStack(spacing: 0) {
                ContactSheet(vm: vm, cardRoot: selectedCard, layout: layout)

                Divider()

                PlanBar(vm: vm, cardRoot: selectedCard)
            }
            .background(Color.surfaceBackground)
            .navigationTitle(cardTitle)
            .navigationSubtitle(cardSubtitle)
        }
        .frame(minWidth: Metrics.windowMinWidth, minHeight: Metrics.windowMinHeight)
        .toolbar { toolbarContent }
        .inspector(isPresented: $showHistory) {
            HistoryInspector(vm: vm)
                .inspectorColumnWidth(min: 260, ideal: 320, max: 480)
        }
        .confirmationDialog(
            moveConfirmationTitle,
            isPresented: $vm.isConfirmingMove,
            titleVisibility: .visible
        ) {
            Button("Move Files", role: .destructive) {
                Task { await vm.importAll() }
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Each file is deleted from the card once its copy has been verified. This cannot be undone.")
        }
    }

    // MARK: - Title

    private var cardTitle: String {
        guard let selectedCard else { return "All Cards" }
        return URL(fileURLWithPath: selectedCard).lastPathComponent
    }

    private var cardSubtitle: String {
        let shown = vm.candidates(onCard: selectedCard)
        guard !shown.isEmpty else { return "No files" }
        let selected = shown.filter { !vm.disabledCandidates.contains($0.id) }.count
        return "\(selected) of \(shown.count) selected"
    }

    private var moveConfirmationTitle: String {
        let count = vm.selectedCandidatesCount
        let noun = count == 1 ? "file" : "files"
        let cards = vm.sourceCardNames
        return cards.isEmpty
            ? "Move \(count) \(noun) off the card?"
            : "Move \(count) \(noun) off \(cards)?"
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            Button {
                vm.refreshVolumes(autoScan: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .iconOnlyLabel("Refresh cards (⌘R)")
            .disabled(vm.isImporting)
        }

        ToolbarItem(placement: .principal) {
            Picker("View", selection: $layout) {
                ForEach(ContactSheetLayout.allCases) { option in
                    Image(systemName: option.symbol)
                        .help(option.title)
                        .tag(option)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .accessibilityLabel("Contact sheet layout")
            .accessibilityValue(layout.title)
            .frame(width: 132)
        }

        ToolbarItem {
            Button {
                showOptions.toggle()
            } label: {
                Label("Options", systemImage: "slider.horizontal.3")
            }
            .help("Import options")
            .popover(isPresented: $showOptions, arrowEdge: .bottom) {
                OptionsPopover(vm: vm)
            }
        }

        ToolbarItem {
            Button {
                showHistory.toggle()
            } label: {
                Label("History", systemImage: "clock.arrow.circlepath")
            }
            .help(showHistory ? "Hide import history" : "Show import history")
            .accessibilityLabel("Import history")
            .badge(vm.unreadProblemCount)
        }

        ToolbarItem(placement: .primaryAction) {
            primaryAction
        }
    }

    @ViewBuilder
    private var primaryAction: some View {
        if vm.isImporting {
            Button {
                vm.cancelImport()
            } label: {
                Text(vm.isCancelling ? "Cancelling…" : "Cancel")
                    .frame(minWidth: 64)
            }
            .buttonStyle(PrimaryActionButtonStyle(role: .destructive))
            .disabled(vm.isCancelling)
            .help("Stop after the file currently being transferred (⌘.)")
        } else {
            Button {
                vm.requestImport()
            } label: {
                Text(vm.options.dryRun ? "Preview" : "Import")
                    .frame(minWidth: 64)
            }
            .buttonStyle(PrimaryActionButtonStyle())
            .disabled(!vm.canStartImport)
            .help(importHelp)
        }
    }

    private var importHelp: String {
        if vm.destinationURL == nil { return "Choose a destination folder first" }
        if vm.selectedCandidatesCount == 0 { return "Select at least one file to import" }
        return vm.importPlanSummary ?? "Start the import (⌘⏎)"
    }
}
