import Foundation

struct ImportOptions {
    enum OrganizationMode: String, CaseIterable, Identifiable {
        case cameraFirst = "Camera/Date"
        case dateFirst = "Date/Camera"
        
        var id: String { rawValue }
    }
    
    var dryRun: Bool = true
    var moveInsteadOfCopy: Bool = false
    var ejectAfterImport: Bool = false
    var organizationMode: OrganizationMode = .cameraFirst
}
