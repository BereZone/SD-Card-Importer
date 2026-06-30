import Foundation

struct ImportOptions {
    enum OrganizationMode: String, CaseIterable, Identifiable {
        case cameraFirst = "Camera/Date"
        case dateFirst = "Date/Camera"
        
        var id: String { rawValue }
    }
    
    enum DateFilter: String, CaseIterable, Identifiable {
        case all = "All Time"
        case sinceLastImport = "Since Last Import"
        case today = "Today"
        case last7Days = "Last 7 Days"
        
        var id: String { rawValue }
    }
    
    var dryRun: Bool = true
    var moveInsteadOfCopy: Bool = false
    var ejectAfterImport: Bool = false
    var openDestinationWhenDone: Bool = true
    var organizationMode: OrganizationMode = .cameraFirst
    var dateFilter: DateFilter = .all
    var renameFiles: Bool = false
    var renameTemplate: String = "{YYYY}-{MM}-{DD}_{Camera}_{OriginalName}"
}
