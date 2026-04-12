#if os(macOS)
import AppKit
import SwiftUI

/// 浮动窗口展示 .inp 中 [PATTERNS] / [CURVES] / [CONTROLS] 章节详情（默认 1000×600 pt）。
/// 三个章节共用一个窗口，在标题栏用分段控件切换。
@MainActor
public final class InpSectionDetailWindowController: NSObject, NSWindowDelegate {

    public static let shared = InpSectionDetailWindowController()

    /// 与具体章节无关的统一窗口标题；「模式 / 曲线 / 控制」在工具栏分段中切换。
    public static let unifiedWindowTitle = "章节"

    private var windowController: NSWindowController?
    private weak var boundAppState: AppState?

    private override init() {
        super.init()
    }

    public func closeWindow() {
        if let wc = windowController {
            wc.close()
        } else {
            boundAppState?.inpSectionDetailKind = nil
        }
    }

    public func show(appState: AppState) {
        guard appState.inpSectionDetailKind != nil else { return }
        boundAppState = appState

        if let wc = windowController, let w = wc.window, w.isVisible {
            w.title = Self.unifiedWindowTitle
            w.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let root = InpSectionDetailRootView()
            .environmentObject(appState)

        let hostingController = NSHostingController(rootView: root)
        hostingController.view.setFrameSize(NSSize(width: 1000, height: 600))

        let window = NSWindow(contentViewController: hostingController)
        window.title = Self.unifiedWindowTitle
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 1000, height: 600))
        window.minSize = NSSize(width: 400, height: 280)
        window.center()
        window.delegate = self

        let wc = NSWindowController(window: window)
        windowController = wc
        wc.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func windowWillClose(_ notification: Notification) {
        boundAppState?.inpSectionDetailKind = nil
        windowController = nil
    }
}

private struct InpSectionDetailRootView: View {
    @EnvironmentObject private var appState: AppState

    private var sectionKindBinding: Binding<InpSectionDetailKind> {
        Binding(
            get: { appState.inpSectionDetailKind ?? .patterns },
            set: { appState.inpSectionDetailKind = $0 }
        )
    }

    var body: some View {
        Group {
            if appState.inpSectionDetailKind != nil {
                NavigationStack {
                    InpSectionDetailView(kind: appState.inpSectionDetailKind!)
                        .navigationTitle("")
                        .toolbar {
                            ToolbarItem(placement: .principal) {
                                Picker("", selection: sectionKindBinding) {
                                    ForEach(InpSectionDetailKind.allCases, id: \.self) { k in
                                        Text(k.toolbarSegmentLabel).tag(k)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .controlSize(.small)
                                .labelsHidden()
                                .frame(maxWidth: 520)
                                .accessibilityLabel("章节")
                            }
                        }
                }
            } else {
                Color.clear
                    .frame(minWidth: 320, minHeight: 200)
            }
        }
    }
}
#endif
