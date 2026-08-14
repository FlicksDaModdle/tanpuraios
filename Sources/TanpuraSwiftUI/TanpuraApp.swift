import SwiftUI

@main
struct TanpuraApp: App {
    @StateObject private var engine = TanpuraEngine()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(engine)
        }
    }
}
