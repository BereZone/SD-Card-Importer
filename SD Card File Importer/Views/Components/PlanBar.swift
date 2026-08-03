import SwiftUI

/// The bar pinned under the contact sheet. It answers "what is about to happen"
/// before an import, "how far along is it" during one, and "what happened" after.
///
/// All three used to be missing. The plan was nowhere — the destination was not
/// shown anywhere in the main window. Progress was a box inside a card. And the
/// outcome was one monospaced line at the bottom of a scrolling console, under a
/// progress bar frozen at 100%, with the file list unchanged. This is the
/// peak-end fix: the last thing the user sees now states, in words, that their
/// footage is safe.
struct PlanBar: View {
    @ObservedObject var vm: ImportViewModel
    let cardRoot: String?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let result = vm.lastResult, !vm.isImporting {
                resultView(result)
            } else if vm.isImporting {
                progressView
            } else {
                planView
            }
        }
        .padding(.horizontal, Metrics.gutter)
        .padding(.vertical, Metrics.regular)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: vm.isImporting)
    }

    // MARK: - Before

    @ViewBuilder
    private var planView: some View {
        if vm.destinationURL == nil {
            message(
                symbol: "folder.badge.questionmark",
                tint: .statusCaution,
                title: "Choose a destination folder",
                detail: "Nothing can be imported until there is somewhere to put it."
            )
        } else if vm.candidates.isEmpty {
            message(
                symbol: "sdcard",
                tint: .secondary,
                title: "No files found",
                detail: vm.removableVolumes.isEmpty
                    ? "Insert a camera card to begin."
                    : "The inserted card has no importable photos or videos."
            )
        } else if vm.selectedCandidatesCount == 0 {
            message(
                symbol: "checklist.unchecked",
                tint: .statusCaution,
                title: "No files selected",
                detail: "Tick at least one file, or press ⌘A to select them all."
            )
        } else {
            operationView
        }
    }

    private var operationView: some View {
        HStack(alignment: .firstTextBaseline, spacing: Metrics.snug) {
            VStack(alignment: .leading, spacing: Metrics.tight) {
                // Source → destination, stated as a sentence. This is the line
                // that makes every destination mistake visible before it happens.
                HStack(spacing: Metrics.snug) {
                    Text(vm.sourceCardNames.isEmpty ? "Selected files" : vm.sourceCardNames)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "arrow.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("to")

                    Text(destinationDescription)
                        .fontWeight(.medium)
                        .lineLimit(1)
                        .truncationMode(.head)
                        .help(vm.destinationURL?.path ?? "")
                }

                HStack(spacing: Metrics.snug) {
                    verificationLight

                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

                    Text(safetyStatement)
                        .font(.caption)
                        .foregroundStyle(vm.importWillDeleteOriginals ? Color.statusCaution : .secondary)
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Metrics.tight) {
                Text("\(vm.selectedCandidatesCount) files")
                    .font(.callout.monospacedDigit())
                Text(vm.formatBytes(Double(vm.pendingImportSize)))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(vm.importPlanSummary ?? "Import plan")
        .accessibilityHint(safetyStatement)
    }

    /// Verification is off by default and roughly doubles the read work, so its
    /// state has to be visible without opening Options — this is the one setting
    /// whose value changes what the completion message is allowed to claim.
    private var verificationLight: some View {
        VerificationIndicator(
            isOn: vm.options.verifyAfterCopy || vm.options.moveInsteadOfCopy,
            isLocked: vm.options.moveInsteadOfCopy,
            isActive: vm.isImporting
        )
    }

    private var destinationDescription: String {
        guard let destination = vm.destinationURL else { return "—" }
        // Show the resolved sub-path for the first selected file, so the folder
        // template, the card's folder assignment and the EXIF date are all
        // visible in their combined effect rather than as four separate inputs.
        if let first = vm.candidates(onCard: cardRoot).first(where: { !vm.disabledCandidates.contains($0.id) }),
           let folder = vm.previewDestinationFolder(for: first), !folder.isEmpty {
            return "\(destination.lastPathComponent)/\(folder)"
        }
        return destination.lastPathComponent
    }

    private var safetyStatement: String {
        if vm.options.dryRun {
            return "Preview only — nothing will be copied or deleted."
        }
        if vm.options.moveInsteadOfCopy {
            return "Each original is deleted from the card only after its copy is verified."
        }
        if vm.options.verifyAfterCopy {
            return "Copies are verified against the originals. Nothing is removed from the card."
        }
        return "Originals stay on the card."
    }

    // MARK: - During

    private var progressView: some View {
        VStack(alignment: .leading, spacing: Metrics.snug) {
            HStack {
                Text(vm.isCancelling ? "Cancelling…" : (vm.options.dryRun ? "Previewing…" : "Importing…"))
                    .fontWeight(.medium)

                verificationLight

                Spacer()

                if !vm.currentTransferSpeed.isEmpty {
                    Text(vm.currentTransferSpeed)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    Text("·")
                        .foregroundStyle(.tertiary)
                    Text(vm.estimatedTimeRemaining)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text("\(Int(vm.progress * 100))%")
                    .font(.caption.monospacedDigit().weight(.semibold))
            }

            ProgressView(value: vm.progress)
                .progressViewStyle(.linear)
                .accessibilityLabel(vm.options.dryRun ? "Preview progress" : "Import progress")
                .accessibilityValue("\(Int(vm.progress * 100)) percent complete")
        }
    }

    // MARK: - After

    private func resultView(_ result: ImportResult) -> some View {
        HStack(alignment: .top, spacing: Metrics.regular) {
            Image(systemName: resultSymbol(result))
                .font(.title2)
                .foregroundStyle(resultTint(result))
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: Metrics.tight) {
                Text(resultHeadline(result))
                    .fontWeight(.medium)

                Text(resultDetail(result))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }

            Spacer()

            HStack(spacing: Metrics.snug) {
                if !result.failed.isEmpty {
                    Button("Retry \(result.failed.count) Failed") {
                        Task { await vm.retryFailedImports() }
                    }
                    .help("Re-import only the files that failed")
                }

                if result.destination != nil && !result.wasDryRun && result.imported > 0 {
                    Button("Show in Finder") {
                        if let destination = result.destination {
                            NSWorkspace.shared.open(destination)
                        }
                    }
                }

                Button("Done") { vm.dismissResult() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(resultHeadline(result)). \(resultDetail(result))")
    }

    private func resultSymbol(_ r: ImportResult) -> String {
        if r.cancelled { return "stop.circle.fill" }
        if !r.failed.isEmpty { return "exclamationmark.triangle.fill" }
        return r.wasDryRun ? "eye.circle.fill" : "checkmark.circle.fill"
    }

    private func resultTint(_ r: ImportResult) -> Color {
        if r.cancelled { return .statusCaution }
        if !r.failed.isEmpty { return .statusDanger }
        return r.wasDryRun ? .brandAccent : .statusSuccess
    }

    private func resultHeadline(_ r: ImportResult) -> String {
        let noun = r.imported == 1 ? "file" : "files"
        if r.cancelled {
            return "Cancelled after \(r.imported) \(noun)"
        }
        if r.wasDryRun {
            return "Previewed \(r.imported) \(noun) — nothing was copied"
        }
        if !r.failed.isEmpty {
            return "Imported \(r.imported) \(noun), \(r.failed.count) failed"
        }
        // The product's core promise, said out loud at the one moment the user
        // is asking the question. It previously appeared only in the README.
        let verb = r.wasMove ? "moved" : "copied"
        return r.verified
            ? "\(r.imported) \(noun) \(verb) and verified"
            : "\(r.imported) \(noun) \(verb)"
    }

    private func resultDetail(_ r: ImportResult) -> String {
        var parts: [String] = []
        if r.bytes > 0 { parts.append(vm.formatBytes(Double(r.bytes))) }
        if r.elapsed > 1 { parts.append("in \(Duration.seconds(Int(r.elapsed)).formatted(.time(pattern: .minuteSecond)))") }
        if r.skipped > 0 { parts.append("\(r.skipped) already present") }
        if r.renamed > 0 { parts.append("\(r.renamed) renamed to avoid a clash") }
        if r.wasMove && r.succeeded && !r.wasDryRun { parts.append("originals removed from the card") }
        if let destination = r.destination { parts.append("→ \(destination.lastPathComponent)") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Shared

    private func message(symbol: String, tint: Color, title: String, detail: String) -> some View {
        HStack(spacing: Metrics.regular) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title). \(detail)")
    }
}
