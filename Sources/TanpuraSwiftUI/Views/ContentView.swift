import SwiftUI

struct ContentView: View {
    @EnvironmentObject var engine: TanpuraEngine

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.06, green: 0.05, blue: 0.09), Color(red: 0.12, green: 0.08, blue: 0.14)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            if engine.isReady {
                ScrollView {
                    VStack(spacing: 20) {
                        Masthead()
                        KeyControlCard()
                        TanpuraPanelView(voice: engine.voice1, title: "Tanpura I")
                        TanpuraPanelView(voice: engine.voice2, title: "Tanpura II")
                    }
                    .padding()
                }
            } else if let error = engine.startupError {
                ErrorView(message: error)
            } else {
                LoadingView()
            }
        }
        .task {
            await engine.start()
        }
        .onDisappear { engine.save() }
    }
}

private struct Masthead: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("तानपुरा")
                .font(.system(size: 34, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
            Text("tanpura")
                .font(.caption)
                .tracking(4)
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding(.top, 12)
    }
}

private struct LoadingView: View {
    var body: some View {
        VStack(spacing: 16) {
            Text("तानपुरा")
                .font(.system(size: 40, weight: .semibold, design: .serif))
                .foregroundStyle(.white)
            ProgressView()
                .tint(.white)
            Text("tuning strings…")
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
    }
}

private struct ErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
            Text("Couldn't load samples")
                .font(.headline)
                .foregroundStyle(.white)
            Text(message)
                .font(.footnote.monospaced())
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(TanpuraEngine())
}
