import SwiftUI
import AVFoundation

struct TanpuraPanelView: View {
    @ObservedObject var voice: TanpuraVoice
    let title: String

    @State private var pulsingString: StringName?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.white)

            if !voice.activeSampleLabel.isEmpty {
                Text(voice.activeSampleLabel)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.5))
            }

            StringVisualizerView(pulsingString: pulsingString)

            NoteButtonRow(voice: voice)

            VStack(spacing: 10) {
                FaderRow(label: "volume", value: $voice.volume, range: 0...1.2)
                FaderRow(label: "L   pan   R", value: $voice.pan, range: -1...1)
            }
        }
        .padding(20)
        .glassCard()
        .onAppear {
            voice.onPluck = { note in
                withAnimation(.easeOut(duration: 0.05)) {
                    pulsingString = note
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    if pulsingString == note {
                        withAnimation(.easeOut(duration: 0.3)) {
                            pulsingString = nil
                        }
                    }
                }
            }
        }
    }
}

private struct FaderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.6))
            Slider(value: $value, in: range)
        }
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        TanpuraPanelView(voice: TanpuraVoice(id: 1, engine: AVAudioEngine(), destination: AVAudioEngine().mainMixerNode), title: "Tanpura I")
            .padding()
    }
}
