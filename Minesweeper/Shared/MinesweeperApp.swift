import SwiftUI

@main
struct MinesweeperApp: App {
    @StateObject private var game = MinesweeperGame()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(game)
                .preferredColorScheme(.light)
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        #endif
    }
}

