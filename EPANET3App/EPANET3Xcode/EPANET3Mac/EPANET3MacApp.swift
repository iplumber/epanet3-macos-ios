import SwiftUI
import EPANET3AppUI

@main
struct EPANET3MacApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("文件") {
                Button("打开 .inp 文件...") {
                    appState.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
