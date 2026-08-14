import SwiftUI

/// Four visual "strings" — 2nd string (Pa/Ma/Ni), two Sa strings (drawn
/// separately so they can alternate pulses, matching the site's
/// alternating-flash behaviour), and Kharaj.
struct StringVisualizerView: View {
    let pulsingString: StringName?
    @State private var saPulseToggle = false

    var body: some View {
        HStack(spacing: 12) {
            stringColumn(label: "2nd", pulsing: pulsingString == .pa || pulsingString == .ma || pulsingString == .ni)
            stringColumn(label: "Sa", pulsing: pulsingString == .sa)
            stringColumn(label: "Sa", pulsing: pulsingString == .sa)
            stringColumn(label: "Kharaj", pulsing: pulsingString == .kharaj)
        }
    }

    private func stringColumn(label: String, pulsing: Bool) -> some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 2)
                .fill(pulsing ? Color.accentColor : Color.white.opacity(0.25))
                .frame(width: 3, height: 56)
                .scaleEffect(y: pulsing ? 1.06 : 1, anchor: .center)
                .shadow(color: pulsing ? .accentColor.opacity(0.8) : .clear, radius: pulsing ? 6 : 0)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
        }
        .frame(maxWidth: .infinity)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        StringVisualizerView(pulsingString: .sa)
    }
}
