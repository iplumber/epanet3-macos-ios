import SwiftUI
import EPANET3AppUI
#if os(macOS)
import AppKit
#endif

@main
struct EPANET3MacApp: App {
    @StateObject private var appState = AppState()
    #if os(macOS)
    @NSApplicationDelegateAdaptor(EPANET3MacApplicationDelegate.self) private var appDelegate
    #endif

    init() {
        _appState = StateObject(wrappedValue: AppState())
        #if os(macOS)
        NotificationCenter.default.addObserver(
            forName: NSApplication.didFinishLaunchingNotification,
            object: nil, queue: .main
        ) { _ in
            ServicesMenuIconCleaner.install()
        }
        #endif
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    #if os(macOS)
                    appDelegate.appState = appState
                    #endif
                    appState.macOpenSettingsHandler = { tab in
                        SettingsWindowController.shared.show(appState: appState, initialTab: tab)
                    }
                }
        }
        .windowToolbarStyle(.unifiedCompact)
        .commands {
            // ── 斗水车菜单 ──
            CommandGroup(replacing: .appInfo) {
                Button("关于斗水车") {
                    NSApp.orderFrontStandardAboutPanel(nil)
                }
            }
            // .appSettings 完全替换：不使用 Settings { } 场景，由此处唯一控制「设置」条目。
            // 标题纯文本「设置」，无图标，⌘, 快捷键，手动打开 SettingsWindowController。
            CommandGroup(replacing: .appSettings) {
                Button("设置") {
                    SettingsWindowController.shared.show(appState: appState)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            // .systemServices 不替换：保留系统「服务」动态子菜单。
            CommandGroup(replacing: .appVisibility) {
                Button("隐藏斗水车") { NSApp.hide(nil) }
                    .keyboardShortcut("h", modifiers: .command)
                Button("隐藏其他") { NSApp.hideOtherApplications(nil) }
                    .keyboardShortcut("h", modifiers: [.command, .option])
                Button("全部显示") { NSApp.unhideAllApplications(nil) }
            }
            CommandGroup(replacing: .appTermination) {
                Button("退出斗水车") { NSApp.terminate(nil) }
                    .keyboardShortcut("q", modifiers: .command)
            }

            // ── 文件菜单 ──
            CommandGroup(replacing: .newItem) {
                Button("新建文件") { appState.newFile() }
                    .keyboardShortcut("n", modifiers: .command)
            }
            CommandGroup(replacing: .saveItem) {}
            CommandGroup(replacing: .undoRedo) {
                Button("撤销") {
                    appState.undo()
                }
                .keyboardShortcut("z", modifiers: .command)
                .disabled(!appState.canUndo || !appState.hasEpanetProject)
                Button("重做") {
                    appState.redo()
                }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(!appState.canRedo || !appState.hasEpanetProject)
            }
            CommandGroup(after: .newItem) {
                Button("打开") { appState.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
                Divider()
                Button("保存") { appState.saveFile() }
                    .keyboardShortcut("s", modifiers: .command)
                Button("另存") { appState.saveAsFile() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Divider()
                Button("关闭") { appState.closeFile() }
                    .keyboardShortcut("w", modifiers: .command)
                Divider()
                Button("运行计算") { appState.runCalculation() }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!appState.canRunHydraulicSolver || appState.isRunning)
            }
            // 并入系统「显示」(View) 菜单，避免与 `CommandMenu("显示")` 重复出现两个同名菜单。
            CommandGroup(after: .sidebar) {
                Divider()
                Button("节点表格…") { appState.openObjectTable(.junction) }
                    .disabled(!appState.hasEpanetProject)
                Button("水塔表格…") { appState.openObjectTable(.tank) }
                    .disabled(!appState.hasEpanetProject)
                Button("水库表格…") { appState.openObjectTable(.reservoir) }
                    .disabled(!appState.hasEpanetProject)
                Button("管段表格…") { appState.openObjectTable(.pipe) }
                    .disabled(!appState.hasEpanetProject)
                Button("阀门表格…") { appState.openObjectTable(.valve) }
                    .disabled(!appState.hasEpanetProject)
                Button("水泵表格…") { appState.openObjectTable(.pump) }
                    .disabled(!appState.hasEpanetProject)
            }
            CommandGroup(after: .pasteboard) {
                Toggle(isOn: Binding(
                    get: { appState.isTopologyEditingEnabled },
                    set: { appState.isTopologyEditingEnabled = $0 }
                )) {
                    Text("允许编辑管网拓扑")
                        .foregroundStyle(appState.isTopologyEditingEnabled ? TopologyEditingAccent.menuOnTint : .primary)
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .tint(TopologyEditingAccent.menuOnTint)
                Divider()
                Button("新增节点") { appState.beginCanvasPlacement(.junction) }
                    .disabled(!appState.isTopologyEditingEnabled)
                Button("新增水塔") { appState.beginCanvasPlacement(.tankTower) }
                    .disabled(!appState.isTopologyEditingEnabled)
                Button("新增水库") { appState.beginCanvasPlacement(.tankPool) }
                    .disabled(!appState.isTopologyEditingEnabled)
                Button("新增管段") { appState.beginCanvasPlacement(.pipe) }
                    .disabled(!appState.isTopologyEditingEnabled)
                Button("新增阀门") { appState.beginCanvasPlacement(.valve) }
                    .disabled(!appState.isTopologyEditingEnabled)
                Button("新增水泵") { appState.beginCanvasPlacement(.pump) }
                    .disabled(!appState.isTopologyEditingEnabled)
                Divider()
                Button("删除选中对象") { appState.deleteSelectedObject() }
                    .disabled(!appState.isTopologyEditingEnabled)
            }
        }
        // ⚠️ 不使用 Settings { } 场景——它会强制注入带齿轮图标和省略号的「设置…」菜单项，
        //    且每次菜单刷新时都会覆盖任何运行时修改，无法去掉图标和省略号。
        //    改用 SettingsWindowController 手动管理窗口。
    }
}

// MARK: - 退出前未保存提示

#if os(macOS)
@MainActor
final class EPANET3MacApplicationDelegate: NSObject, NSApplicationDelegate {
    weak var appState: AppState?

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState, appState.hasUnsavedChanges else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "是否保存对文件的更改？"
        alert.informativeText = "您有尚未保存到 .inp 的修改。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            appState.saveFile()
            if appState.errorMessage != nil { return .terminateCancel }
            if appState.hasUnsavedChanges { return .terminateCancel }
            return .terminateNow
        case .alertSecondButtonReturn:
            return .terminateNow
        default:
            return .terminateCancel
        }
    }
}
#endif

// MARK: - 设置窗口控制器（替代 Settings { } 场景）

#if os(macOS)
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {

    static let shared = SettingsWindowController()

    private var windowController: NSWindowController?
    private weak var currentAppState: AppState?
    /// 按下 ESC（keyCode 53）关闭设置窗口
    private var escapeKeyMonitor: Any?

    func show(appState: AppState, initialTab: Int? = nil) {
        currentAppState = appState
        if let tab = initialTab {
            appState.settingsPendingToolbarTab = tab
        }

        if let wc = windowController, let window = wc.window, window.isVisible {
            installEscapeMonitor(for: window)
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let rootView = SettingsView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: rootView)
        hostingController.view.setFrameSize(NSSize(width: 720, height: 640))

        let window = NSWindow(contentViewController: hostingController)
        window.title = "设置"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 640))
        window.minSize = NSSize(width: 560, height: 380)
        window.center()
        // 相对居中位置整体下移 100pt（屏幕坐标 y 向上为正）
        var frame = window.frame
        frame.origin.y -= 100
        window.setFrameOrigin(frame.origin)
        window.delegate = self

        let wc = NSWindowController(window: window)
        windowController = wc
        installEscapeMonitor(for: window)
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func installEscapeMonitor(for window: NSWindow) {
        removeEscapeMonitor()
        escapeKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak window] event in
            guard let window, window.isKeyWindow else { return event }
            if event.keyCode == 53 {
                window.close()
                return nil
            }
            return event
        }
    }

    private func removeEscapeMonitor() {
        if let escapeKeyMonitor {
            NSEvent.removeMonitor(escapeKeyMonitor)
            self.escapeKeyMonitor = nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        removeEscapeMonitor()
        windowController = nil
    }
}

// MARK: - 服务菜单图标清除

/// 仅去掉「服务」父项左侧图标，保留其动态子菜单内容。
/// 「服务」是系统 NSMenuItem（非 SwiftUI 管理），menuWillOpen 在绘制前同步调用，改一次即可。
final class ServicesMenuIconCleaner: NSObject, NSMenuDelegate {
    static let shared = ServicesMenuIconCleaner()

    /// 在 didFinishLaunching 后调用一次即可完成安装。
    static func install() {
        guard let appSubmenu = NSApp.mainMenu?.items.first?.submenu else { return }
        appSubmenu.delegate = shared
        shared.menuWillOpen(appSubmenu) // 立即清一次，处理已存在的状态
    }

    func menuWillOpen(_ menu: NSMenu) {
        for item in menu.items {
            guard item.submenu != nil,
                  item.title == "服务" || item.title == "Services" else { continue }
            item.image = nil
            item.onStateImage = nil
            item.offStateImage = nil
            item.mixedStateImage = nil
            break
        }
    }
}
#endif
