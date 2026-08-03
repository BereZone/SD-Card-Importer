import SwiftUI

/// Import options, in a toolbar popover attached to the control that uses them.
///
/// These were six switches and a picker sitting permanently on the main screen —
/// a decision point with six simultaneous options, in a window where nothing was
/// the subject. They are settings for an operation, so they belong next to the
/// operation and out of the way the rest of the time.
struct OptionsPopover: View {
    @ObservedObject var vm: ImportViewModel

    var body: some View {
        Form {
            Section {
                Picker("Files from", selection: $vm.options.dateFilter) {
                    ForEach(ImportOptions.DateFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                }

                if vm.options.dateFilter == .customRange {
                    DatePicker("From", selection: $vm.options.customStartDate, displayedComponents: .date)
                    DatePicker("To", selection: $vm.options.customEndDate, displayedComponents: .date)
                }
            }

            Section {
                Picker("Operation", selection: $vm.options.moveInsteadOfCopy) {
                    Text("Copy — originals stay on the card").tag(false)
                    Text("Move — originals are deleted").tag(true)
                }
                .pickerStyle(.radioGroup)
                .accessibilityHint(vm.options.moveInsteadOfCopy
                    ? "Each original is deleted from the card after its copy is verified"
                    : "Nothing is removed from the card")

                Toggle("Verify copies against originals", isOn: Binding(
                    get: { vm.options.verifyAfterCopy || vm.options.moveInsteadOfCopy },
                    set: { vm.options.verifyAfterCopy = $0 }
                ))
                // Moving without verifying would mean deleting an original that
                // was never checked, so the control locks and says why rather
                // than greying out silently.
                .disabled(vm.options.moveInsteadOfCopy)
                .help(vm.options.moveInsteadOfCopy
                    ? "Always on when moving — an original is never deleted unverified"
                    : "Re-reads each copy and compares it to the source. Slower, and the reason to trust the result.")

                if vm.options.moveInsteadOfCopy {
                    Label("Always on when moving files", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Operation")
            }

            Section {
                Toggle("Preview only — do not copy anything", isOn: $vm.options.dryRun)
                    .help("Runs the whole plan and reports what would happen, without touching a file")

                Toggle("Eject cards when finished", isOn: $vm.options.ejectAfterImport)
                    .help("Skipped automatically if any file fails")

                Toggle("Open the destination when finished", isOn: $vm.options.openDestinationWhenDone)
            } header: {
                Text("After")
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .frame(maxHeight: 460)
        .scrollBounceBehavior(.basedOnSize)
    }
}
