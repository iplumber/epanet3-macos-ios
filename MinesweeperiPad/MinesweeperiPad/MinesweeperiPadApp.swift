import SwiftUI

@main
struct MinesweeperiPadApp: App {
    @StateObject private var game = MinesweeperGame()

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .navigationTitle("Minesweeper")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .environmentObject(game)
            .preferredColorScheme(.light)
        }
    }
}

