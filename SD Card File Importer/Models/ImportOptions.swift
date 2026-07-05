import Foundation

struct ImportOptions {

    
    enum DateFilter: String, CaseIterable, Identifiable {
        case all = "All Time"
        case sinceLastImport = "Since Last Import"
        case today = "Today"
        case last7Days = "Last 7 Days"
        case customRange = "Custom Range"
        
        var id: String { rawValue }
    }
    
    var dryRun: Bool = true
    var moveInsteadOfCopy: Bool = false
    var ejectAfterImport: Bool = false
    var openDestinationWhenDone: Bool = true
    var folderTemplate: String = "{Camera}/{YYYY}/{MM}/{DD}"
    var dateFilter: DateFilter = .all
    var renameFiles: Bool = false
    var renameTemplate: String = "{YYYY}-{MM}-{DD}_{Camera}_{OriginalName}"
    var customStartDate: Date = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
    var customEndDate: Date = Date()
}
