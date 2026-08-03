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

    /// One `ToolbarItemGroup` per side, and no `.principal` placement.
    ///
    /// `.principal` centres an item in the title area and pushes everything else
    /// outward, which made AppKit collapse the trailing buttons into an overflow
    /// "»" menu as soon as the window was anything short of wide. That also broke
    /// Options outright: a popover anchored to a button that has been folded into
    /// the overflow menu has no anchor left to present from, so the click
    /// registered and nothing appeared.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                vm.refreshVolumes(autoScan: true)
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .iconOnlyLabel("Refresh cards (⌘R)")
            .disabled(vm.isImporting)

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
        }

        ToolbarItemGroup(placement: .primaryAction) {
            optionsButton
            historyButton
            primaryAction
        }
    }

    private var optionsButton: some View {
        Button {
            showOptions.toggle()
        } label: {
            Label("Options", systemImage: "slider.horizontal.3")
        }
        .help("Import options")
        // Anchored to a button that is always visible in the toolbar, so the
        // popover always has something to point at.
        .popover(isPresented: $showOptions, arrowEdge: .bottom) {
            OptionsPopover(vm: vm)
        }
    }

    private var historyButton: some View {
        Button {
            showHistory.toggle()
        } label: {
            // `.badge` does nothing on a macOS toolbar button, so the count goes
            // in the label where it can actually be seen and read aloud.
            Label(
                vm.unreadProblemCount > 0 ? "History (\(vm.unreadProblemCount))" : "History",
                systemImage: "clock.arrow.circlepath"
            )
        }
        .help(showHistory ? "Hide import history" : "Show import history")
        .accessibilityLabel(
            vm.unreadProblemCount > 0
                ? "Import history, \(vm.unreadProblemCount) problems"
                : "Import history"
        )
    }

    /// Filled rather than bordered, so the one button that starts moving files
    /// never reads as a peer of the two that open panels.
    @ViewBuilder
    private var primaryAction: some View {
        if vm.isImporting {
            Button {
                vm.cancelImport()
            } label: {
                Text(vm.isCancelling ? "Cancelling…" : "Cancel")
            }
            .buttonStyle(.borderedProminent)
            .tint(.statusDanger)
            .disabled(vm.isCancelling)
            .help("Stop after the file currently being transferred (⌘.)")
        } else {
            Button {
                vm.requestImport()
            } label: {
                Text(vm.options.dryRun ? "Preview" : "Import")
            }
            .buttonStyle(.borderedProminent)
            .tint(vm.importWillDeleteOriginals ? .statusDanger : .brandAccent)
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
