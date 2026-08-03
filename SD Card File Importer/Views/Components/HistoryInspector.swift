import SwiftUI

/// The import history, demoted from a permanent third of the window to an
/// inspector you open when you want it.
///
/// It used to be the only place the app reported anything — scan results, skips,
/// renames, verification, errors and completion all lived here and nowhere else,
/// which is why it had to be always visible. Now that each of those has a real
/// home, this is what it should always have been: a record you consult, with
/// timestamps, because a forty-minute import deserves one.
struct HistoryInspector: View {
    @ObservedObject var vm: ImportViewModel
    @State private var onlyProblems = false

    private var entries: [LogEntry] {
        onlyProblems
            ? vm.logLines.filter { $0.severity == .failure || $0.severity == .caution }
            : vm.logLines
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if entries.isEmpty {
                EmptyStateView(
                    symbol: "clock",
                    title: onlyProblems ? "No problems" : "Nothing yet",
                    message: onlyProblems
                        ? "Every event so far has been routine."
                        : "Scans and imports are recorded here as they happen."
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(entries) { entry in
                                row(entry).id(entry.id)
                            }
                        }
                        .padding(.vertical, Metrics.snug)
                    }
                    .onChange(of: vm.logLines.count) {
                        if let last = entries.last {
                            withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                        }
                    }
                }
            }
        }
        .background(Color.surfaceBackground)
    }

    private var header: some View {
        HStack {
            Text("History").font(.headline)
            Spacer()
            Toggle("Problems only", isOn: $onlyProblems)
                .toggleStyle(.switch)
                .controlSize(.mini)
                .help("Show only warnings and failures")
            Button {
                exportLog()
            } label: {
                Image(systemName: "square.and.arrow.up")
            }
            .buttonStyle(.plain)
            .iconOnlyLabel("Export history to a text file")
            .disabled(vm.logLines.isEmpty)
        }
        .padding(.horizontal, Metrics.regular)
        .padding(.vertical, Metrics.snug)
        .background(.bar)
    }

    private func row(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: Metrics.snug) {
            Image(systemName: entry.severity.symbol)
                .font(.caption)
                .foregroundStyle(entry.severity.tint)
                .frame(width: 14)
                .accessibilityHidden(true)

            Text(entry.timeLabel)
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.tertiary)

            Text(entry.text)
                .font(.caption)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, Metrics.regular)
        .padding(.vertical, 3)
        // Severity is spoken, not left to an icon or a colour.
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.severity.accessibilityDescription) at \(entry.timeLabel). \(entry.text)")
    }

    private func exportLog() {
        let panel = NSSavePanel()
        panel.title = "Export Import History"
        panel.nameFieldStringValue = "import-history.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let body = vm.logLines
            .map { "\($0.timeLabel)\t\($0.severity.rawValue)\t\($0.text)" }
            .joined(separator: "\n")
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }
}
