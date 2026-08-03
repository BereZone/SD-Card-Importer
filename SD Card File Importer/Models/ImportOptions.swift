import Foundation

nonisolated struct ImportOptions: Codable {


    enum DateFilter: String, CaseIterable, Identifiable, Codable {
        case all = "All Time"
        case sinceLastImport = "Since Last Import"
        case today = "Today"
        case last7Days = "Last 7 Days"
        case customRange = "Custom Range"
        
        var id: String { rawValue }
    }
    
    /// Ships off. Copying never destroys anything, so a preview-by-default gains
    /// no safety — it only meant a new user's first import did nothing and
    /// reported "Done. Imported 0/482", which reads as total failure.
    var dryRun: Bool = false
    var moveInsteadOfCopy: Bool = false
    /// Re-read each copied file from the destination (uncached) and compare its
    /// SHA-256 hash against the source. Moves always verify regardless of this flag.
    ///
    /// Ships on. A verified import is the product's central promise; shipping it
    /// off meant the default configuration did not deliver it.
    var verifyAfterCopy: Bool = true
    var ejectAfterImport: Bool = false
    var openDestinationWhenDone: Bool = true
    var folderTemplate: String = "{Camera}/{YYYY}/{MM}/{DD}"
    var dateFilter: DateFilter = .all
    var renameFiles: Bool = false
    var renameTemplate: String = "{YYYY}-{MM}-{DD}_{Camera}_{OriginalName}"
    var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    var customEndDate: Date = Date()
}
