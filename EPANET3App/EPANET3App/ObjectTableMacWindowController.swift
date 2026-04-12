#if os(macOS)
import AppKit
import SwiftUI

/// 独立浮动窗口展示对象表，非模态：可与主窗口画布同时操作。
@MainActor
public final class ObjectTableWindowController: NSObject, NSWindowDelegate {

    public static let shared = ObjectTableWindowController()

    private static let windowTitle = "对象表"

    private var windowController: NSWindowController?
    private weak var boundAppState: AppState?

    private override init() {
        super.init()
    }

    /// 关闭对象表窗口（若存在）；无窗口时仅用于配合 `AppState` 复位。
    public func closeWindow() {
        if let wc = windowController {
            wc.close()
        } else {
            boundAppState?.objectTableSheetKind = nil
        }
    }

    public func show(appState: AppState) {
        guard appState.objectTableSheetKind != nil else { return }
        boundAppState = appState

        if let wc = windowController, let w = wc.window, w.isVisible {
            w.title = Self.windowTitle
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Self.clearKeyboardFocus(in: w)
            return
        }

        let root = ObjectTableWindowRootView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: root)
        hostingController.view.setFrameSize(NSSize(width: 920, height: 520))

        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.windowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 920, height: 520))
        window.minSize = NSSize(width: 880, height: 380)
        window.center()
        window.delegate = self

        let wc = NSWindowController(window: window)
        windowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.clearKeyboardFocus(in: window)
    }

    /// 表格窗口出现时不要让 `NSTextField` 单元格抢占第一响应者，光标保持失焦。
    private static func clearKeyboardFocus(in window: NSWindow) {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                window.makeFirstResponder(nil)
            }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        boundAppState?.objectTableSheetKind = nil
        windowController = nil
    }
}

private struct ObjectTableWindowRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if appState.objectTableSheetKind != nil {
                ObjectTableTabsView()
                    .environmentObject(appState)
            } else {
                Color.clear
                    .frame(minWidth: 400, minHeight: 300)
            }
        }
    }
}
#endif
