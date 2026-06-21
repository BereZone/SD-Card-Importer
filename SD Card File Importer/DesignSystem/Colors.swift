import SwiftUI
import AppKit

extension Color {
    // Primary brand colors with vibrant accents
    static let accentPrimary = Color(red: 0.4, green: 0.6, blue: 1.0)  // Modern blue
    static let accentSecondary = Color(red: 0.5, green: 0.3, blue: 0.9) // Purple
    static let successGreen = Color(red: 0.2, green: 0.8, blue: 0.4)
    static let warningOrange = Color(red: 1.0, green: 0.6, blue: 0.2)
    static let errorRed = Color(red: 1.0, green: 0.3, blue: 0.3)
    
    // Card backgrounds with adaptive dark/light mode
    static let cardBackground = Color(NSColor.controlBackgroundColor).opacity(0.6)
    static let cardBackgroundSecondary = Color(NSColor.windowBackgroundColor).opacity(0.8)
}
