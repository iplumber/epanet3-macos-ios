/* EPANET 3 App - macOS / iOS (Phase 5: iPad mini A17, iPhone 15 Pro)
 * Opens .inp files and renders network with Metal.
 */
import SwiftUI
import EPANET3AppUI

@main
struct EPANET3App: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                #if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                #endif
        }
        #if os(macOS)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("文件") {
                Button("打开 .inp 文件...") {
                    appState.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
        #endif
    }
}
