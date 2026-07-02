import SwiftUI

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    
    var id: String { rawValue }
    
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

enum UIDensity: String, CaseIterable, Identifiable {
    case comfortable = "Comfortable"
    case compact = "Compact"
    
    var id: String { rawValue }
}
