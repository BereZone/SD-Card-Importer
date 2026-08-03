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

                PlanBar(vm: vm, cardRoot: selectedCard, showOptions: $showOptions, showHistory: $showHistory)
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

    /// Only the two view controls live here.
    ///
    /// Options, History and the primary action moved to the plan bar, because a
    /// macOS toolbar refuses to hold them reliably: a `ToolbarItemGroup`
    /// collapses into an overflow menu when space is tight — which also strands
    /// any popover anchored to a collapsed item — and a `.borderedProminent`
    /// button loses its fill once AppKit adopts it, so the primary action
    /// stopped reading as a button. Refresh and the layout switcher are plain
    /// enough to survive as toolbar items.
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button {
                // Clears the hidden-card list too, so Refresh genuinely means
                // "look again" rather than "look again, minus whatever I
                // removed by accident".
                vm.clearIgnoresAndRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .iconOnlyLabel("Refresh cards, restoring any you removed (⌘R)")
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

    }

}
