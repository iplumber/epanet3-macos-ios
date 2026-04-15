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
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") { appState.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                    .disabled(!appState.canUndo || !appState.hasEpanetProject)
                Button("重做") { appState.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
                    .disabled(!appState.canRedo || !appState.hasEpanetProject)
            }
            CommandMenu("文件") {
                Button("新建文件") {
                    appState.newFile()
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("打开") {
                    appState.openFile()
                }
                .keyboardShortcut("o", modifiers: .command)
                Menu("导入") {
                    Button("SCADA…") {
                        appState.importScadaDeviceCSVsMac()
                    }
                    Button("SHP 文件…") {}
                        .disabled(true)
                }
                .disabled(appState.filePath == nil || (appState.filePath?.isEmpty ?? true))
            }
        }
        #endif
    }
}
