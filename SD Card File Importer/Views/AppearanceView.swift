import SwiftUI

struct AppearanceView: View {
    @AppStorage("appTheme") private var appTheme: AppTheme = .system
    @AppStorage("uiDensity") private var uiDensity: UIDensity = .comfortable
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "paintbrush.fill")
                    .font(.system(size: 24))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.accentPrimary, .accentSecondary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                VStack(alignment: .leading, spacing: 1) {
                    Text("Appearance")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                    Text("Customize the look and feel of the app")
                        .font(.system(.caption, design: .rounded))
                        .foregroundColor(.secondary)
                }
            }
            .padding(.bottom, 10)
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Theme")
                    .sectionHeader()
                
                Picker("Theme", selection: $appTheme) {
                    ForEach(AppTheme.allCases) { theme in
                        Text(theme.rawValue).tag(theme)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
                
                Divider()
                    .padding(.vertical, 8)
                
                Text("UI Density")
                    .sectionHeader()
                
                Picker("Density", selection: $uiDensity) {
                    ForEach(UIDensity.allCases) { density in
                        Text(density.rawValue).tag(density)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 300)
            }
            .modernCard(accentColor: .accentPrimary)
            
            Spacer()
        }
        .padding(24)
        .frame(minWidth: 400, minHeight: 400, alignment: .topLeading)
    }
}
