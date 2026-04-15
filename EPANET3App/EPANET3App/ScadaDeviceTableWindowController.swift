#if os(macOS)
import AppKit
import SwiftUI

/// 侧栏「压力 / 流量」设备对应表：独立浮动窗口，非模态（可与主窗口同时操作）。
@MainActor
public final class ScadaDeviceTableWindowController: NSObject, NSWindowDelegate {

    public static let shared = ScadaDeviceTableWindowController()

    private var windowController: NSWindowController?
    private weak var boundAppState: AppState?

    private override init() {
        super.init()
    }

    private static func windowTitle(for kind: ScadaDeviceKind) -> String {
        switch kind {
        case .pressure: return "压力设备对应表"
        case .flow: return "流量设备对应表"
        }
    }

    public func closeWindow() {
        if let wc = windowController {
            wc.close()
        } else {
            boundAppState?.scadaDeviceTableWindowKind = nil
        }
    }

    public func show(appState: AppState) {
        guard let kind = appState.scadaDeviceTableWindowKind else { return }
        boundAppState = appState
        let title = Self.windowTitle(for: kind)

        if let wc = windowController, let w = wc.window, w.isVisible {
            w.title = title
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            Self.clearKeyboardFocus(in: w)
            return
        }

        let root = ScadaDeviceTableWindowRootView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: root)
        hostingController.view.setFrameSize(NSSize(width: 720, height: 520))

        let window = NSWindow(contentViewController: hostingController)
        window.title = title
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 720, height: 520))
        window.minSize = NSSize(width: 560, height: 320)
        window.center()
        window.delegate = self

        let wc = NSWindowController(window: window)
        windowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        Self.clearKeyboardFocus(in: window)
    }

    private static func clearKeyboardFocus(in window: NSWindow) {
        DispatchQueue.main.async {
            DispatchQueue.main.async {
                window.makeFirstResponder(nil)
            }
        }
    }

    public func windowWillClose(_ notification: Notification) {
        boundAppState?.scadaDeviceTableWindowKind = nil
        windowController = nil
    }
}

private struct ScadaDeviceTableWindowRootView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Group {
            if let kind = appState.scadaDeviceTableWindowKind {
                let devices = kind == .pressure ? appState.scadaPressureDevices : appState.scadaFlowDevices
                ScadaDeviceTablePanel(kind: kind, devices: devices)
            } else {
                Color.clear
                    .frame(minWidth: 400, minHeight: 240)
            }
        }
    }
}
#endif
