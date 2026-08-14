import SwiftUI

struct KeyControlCard: View {
    @EnvironmentObject var engine: TanpuraEngine

    var body: some View {
        VStack(spacing: 16) {
            // Key stepper
            HStack(spacing: 20) {
                ArrowButton(systemName: "minus", enabled: engine.canLowerKey) {
                    engine.lowerKey()
                }
                let key = engine.keyLabel
                HStack(alignment: .top, spacing: 2) {
                    Text(key.name)
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                    Text("\(key.octave)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .baselineOffset(14)
                }
                .foregroundStyle(.white)
                ArrowButton(systemName: "plus", enabled: engine.canRaiseKey) {
                    engine.raiseKey()
                }
            }

            // Fine tune
            HStack {
                Image(systemName: "flat")
                Slider(
                    value: Binding(
                        get: { engine.fineCents },
                        set: { engine.setFineCents($0) }
                    ),
                    in: -50...50,
                    step: 1
                )
                Image(systemName: "sharp")
                Text(fineTuneLabel)
                    .font(.caption.monospacedDigit())
                    .frame(width: 48, alignment: .trailing)
            }
            .foregroundStyle(.white.opacity(0.85))

            // Tempo
            HStack {
                Text("bpm")
                    .font(.caption)
                Slider(value: $engine.tempoBpm, in: 40...200, step: 1)
                Text("\(Int(engine.tempoBpm))")
                    .font(.caption.monospacedDigit())
                    .frame(width: 32, alignment: .trailing)
            }
            .foregroundStyle(.white.opacity(0.85))

            Toggle("vary tempos", isOn: $engine.varyTempo)
                .toggleStyle(.switch)
                .foregroundStyle(.white.opacity(0.85))

            Toggle("alt tanpura (male voice)", isOn: $engine.altVoice)
                .toggleStyle(.switch)
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(20)
        .glassCard()
    }

    private var fineTuneLabel: String {
        let semitoneValue = engine.fineCents / 100
        let sign = semitoneValue > 0 ? "+" : (semitoneValue < 0 ? "" : "±")
        return "\(sign)\(String(format: "%.2f", semitoneValue))"
    }
}

private struct ArrowButton: View {
    let systemName: String
    let enabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2.weight(.semibold))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.glass)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.35)
    }
}

/// Shared Liquid Glass card styling. Uses the iOS 26 `.glassEffect()` API
/// where available; falls back to a translucent material on older SDKs so
/// the project still builds against earlier toolchains if needed.
struct GlassCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .glassEffect(.regular, in: .rect(cornerRadius: 24))
        } else {
            content
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24))
        }
    }
}

extension View {
    func glassCard() -> some View {
        modifier(GlassCardModifier())
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        KeyControlCard()
            .environmentObject(TanpuraEngine())
            .padding()
    }
}
