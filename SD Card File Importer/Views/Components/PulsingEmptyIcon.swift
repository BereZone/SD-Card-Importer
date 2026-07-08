import SwiftUI

struct PulsingEmptyIcon: View {
    let systemName: String
    @State private var isPulsing = false
    
    var body: some View {
        ZStack {
            Circle()
                .fill(Color.accentSecondary.opacity(0.1))
                .frame(width: 80, height: 80)
                .scaleEffect(isPulsing ? 1.2 : 0.8)
                .opacity(isPulsing ? 0 : 1)
                .animation(.easeInOut(duration: 2).repeatForever(autoreverses: false), value: isPulsing)
            
            Circle()
                .fill(Color.accentSecondary.opacity(0.1))
                .frame(width: 60, height: 60)
            
            Image(systemName: systemName)
                .font(.system(size: 28, weight: .light))
                .foregroundColor(.accentSecondary)
        }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                isPulsing = true
            }
        }
    }
}
