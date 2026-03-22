import SwiftUI
import UniformTypeIdentifiers
import Metal
import EPANET3Renderer
import EPANET3Bridge
#if canImport(UIKit)
import UIKit
#endif
#if os(macOS)
import AppKit
#endif

private enum AppColors {
    static var controlBackground: Color {
        #if os(macOS)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(UIColor.secondarySystemBackground)
        #endif
    }
    static var windowBackground: Color {
        #if os(macOS)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color(UIColor.systemBackground)
        #endif
    }
}

public struct ContentView: View {
    @EnvironmentObject var appState: AppState
    public init() {}
    @State private var scale: CGFloat = 1
    @State private var panX: CGFloat = 0
    @State private var panY: CGFloat = 0
    @State private var lastScale: CGFloat = 1
    @State private var lastPan: CGSize = .zero
    @State private var mouseSceneX: Float?
    @State private var mouseSceneY: Float?
    @State private var showRunResultSheet = false
    @State private var resultLegendOffset: CGSize = .zero
    @State private var resultLegendLastOffset: CGSize = .zero
    @State private var showLeftSidebar = true
    @State private var showRightPanel = true

    private var nodeRange: (Float, Float)? {
        guard !appState.nodePressureValues.isEmpty else { return nil }
        guard let minV = appState.nodePressureValues.min(), let maxV = appState.nodePressureValues.max() else { return nil }
        return (minV, maxV)
    }

    private var linkRange: (Float, Float)? {
        guard !appState.linkFlowValues.isEmpty else { return nil }
        guard let minV = appState.linkFlowValues.min(), let maxV = appState.linkFlowValues.max() else { return nil }
        return (minV, maxV)
    }

    #if os(macOS)
    private var displayFileName: String {
        guard let path = appState.filePath, !path.isEmpty else { return "" }
        return URL(fileURLWithPath: path).lastPathComponent
    }
    #endif

    private func centerView(on target: (x: Float, y: Float), in scene: NetworkScene) {
        let centerX = (scene.bounds.minX + scene.bounds.maxX) * 0.5
        let centerY = (scene.bounds.minY + scene.bounds.maxY) * 0.5
        panX = CGFloat((centerX - target.x) / 0.01)
        panY = CGFloat((target.y - centerY) / 0.01)
        lastPan = CGSize(width: panX, height: panY)
    }

    private func focusOnCurrentSelection(in scene: NetworkScene) {
        if let nodeIndex = appState.selectedNodeIndex,
           let node = scene.nodes.first(where: { $0.nodeIndex == nodeIndex }) {
            centerView(on: (node.x, node.y), in: scene)
            return
        }
        if let linkIndex = appState.selectedLinkIndex,
           let link = scene.links.first(where: { $0.linkIndex == linkIndex }) {
            centerView(on: ((link.x1 + link.x2) * 0.5, (link.y1 + link.y2) * 0.5), in: scene)
        }
    }

    public var body: some View {
        mainContent
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(macOS)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text(displayFileName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.primary)
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showLeftSidebar.toggle()
                } label: {
                    Image(systemName: "sidebar.leading")
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(showLeftSidebar ? 0.3 : 0), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(showLeftSidebar ? "隐藏图例列表" : "显示图例列表")

                Button {
                    showRightPanel.toggle()
                } label: {
                    Image(systemName: "sidebar.trailing")
                        .overlay(
                            RoundedRectangle(cornerRadius: 4)
                                .stroke(Color.primary.opacity(showRightPanel ? 0.3 : 0), lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .help(showRightPanel ? "隐藏属性列表" : "显示属性列表")
            }
        }
        #elseif os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("打开") { appState.openFile() }
            }
        }
        #endif
        .fileImporter(isPresented: $appState.showFileImporter, allowedContentTypes: [UTType(filenameExtension: "inp") ?? .plainText], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            appState.openFileFromURL(url)
        }
        .sheet(isPresented: $showRunResultSheet) {
            RunResultSheet(result: appState.runResult)
        }
        #if os(macOS)
        .onAppear { updateMacWindowTitle() }
        .onChange(of: appState.filePath) { _ in updateMacWindowTitle() }
        #endif
    }

    @ViewBuilder
    private var mainContent: some View {
        VStack(spacing: 0) {
            if let msg = appState.errorMessage {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundColor(.orange)
                    Text(msg)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(8)
                .background(Color.orange.opacity(0.1))
            }

            if appState.isLoading {
                Spacer()
                ProgressView("加载中...")
                Spacer()
            } else if let scene = appState.scene {
                if appState.project != nil {
                    #if os(macOS)
                    MacDesignToolbar(appState: appState)
                    #else
                    HStack(spacing: 8) {
                        Button { appState.setEditorMode(.browse) } label: { Label("浏览", systemImage: "hand.tap") }
                            .buttonStyle(.bordered)
                            .tint(appState.editorMode == .browse ? .accentColor : .gray)
                        Button { appState.setEditorMode(.add) } label: { Label("添加", systemImage: "plus.circle") }
                            .buttonStyle(.bordered)
                            .tint(appState.editorMode == .add ? .accentColor : .gray)
                        Button { appState.setEditorMode(.delete) } label: { Label("删除", systemImage: "trash") }
                            .buttonStyle(.bordered)
                            .tint(appState.editorMode == .delete ? .accentColor : .gray)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.controlBackground)
                    #endif
                }
                HStack(spacing: 0) {
                    #if os(macOS)
                    if showLeftSidebar {
                        MacDesignSidebar(appState: appState)
                            .frame(width: 200)
                            .background(DesignSurfaceBackground())
                    }
                    #endif

                    ZStack {
                        CanvasBackgroundView()
                            .overlay(CanvasGridView())
                        MetalNetworkView(
                            scene: scene,
                            scale: scale,
                            panX: panX,
                            panY: panY,
                            selectedNodeIndex: appState.selectedNodeIndex,
                            selectedLinkIndex: appState.selectedLinkIndex,
                            nodeScalars: appState.resultOverlayMode == .pressure ? appState.nodePressureValues : nil,
                            linkScalars: appState.resultOverlayMode == .flow ? appState.linkFlowValues : nil,
                            nodeScalarRange: appState.resultOverlayMode == .pressure ? nodeRange : nil,
                            linkScalarRange: appState.resultOverlayMode == .flow ? linkRange : nil,
                            clearColor: MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
                        ) { delta, viewPoint, viewSize in
                            let newScale = max(0.2, min(20, scale * (1 + delta)))
                            if viewSize.width > 0, viewSize.height > 0 {
                                let w = Float(viewSize.width), h = Float(viewSize.height)
                                let ndcX = 2 * Float(viewPoint.x) / w - 1
                                let ndcY = 1 - 2 * Float(viewPoint.y) / h
                                let bw = scene.bounds.maxX - scene.bounds.minX
                                let bh = scene.bounds.maxY - scene.bounds.minY
                                let pad = max(bw, bh) * 0.05 + 1
                                let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
                                let (scaleXOld, scaleYOld): (Float, Float)
                                if w >= h {
                                    scaleYOld = baseScale * Float(scale)
                                    scaleXOld = scaleYOld * h / w
                                } else {
                                    scaleXOld = baseScale * Float(scale)
                                    scaleYOld = scaleXOld * w / h
                                }
                                let centerX = (scene.bounds.minX + scene.bounds.maxX) * 0.5
                                let centerY = (scene.bounds.minY + scene.bounds.maxY) * 0.5
                                let offXOld = -centerX * scaleXOld + Float(panX) * scaleXOld * 0.01
                                let offYOld = -centerY * scaleYOld - Float(panY) * scaleYOld * 0.01
                                let sceneX = (ndcX - offXOld) / scaleXOld
                                let sceneY = (ndcY - offYOld) / scaleYOld
                                let (scaleXNew, scaleYNew): (Float, Float)
                                if w >= h {
                                    scaleYNew = baseScale * Float(newScale)
                                    scaleXNew = scaleYNew * h / w
                                } else {
                                    scaleXNew = baseScale * Float(newScale)
                                    scaleYNew = scaleXNew * w / h
                                }
                                let offXNew = ndcX - sceneX * scaleXNew
                                let offYNew = ndcY - sceneY * scaleYNew
                                panX = CGFloat((offXNew + centerX * scaleXNew) / (scaleXNew * 0.01))
                                panY = CGFloat(-(offYNew + centerY * scaleYNew) / (scaleYNew * 0.01))
                            }
                            scale = newScale
                            lastScale = scale
                            lastPan = CGSize(width: panX, height: panY)
                        } onPanDelta: { dx, dy, viewSize in
                            guard viewSize.width > 0, viewSize.height > 0 else { return }
                            // 仅移动视窗 (panX/panY)，节点与管段坐标不变；XY 比例一致
                            let w = Float(viewSize.width), h = Float(viewSize.height)
                            let bw = scene.bounds.maxX - scene.bounds.minX
                            let bh = scene.bounds.maxY - scene.bounds.minY
                            let pad = max(bw, bh) * 0.05 + 1
                            let baseScale = min(2.0 / (bw + pad * 2), 2.0 / (bh + pad * 2))
                            let s = baseScale * Float(scale)
                            let (scaleX, scaleY): (Float, Float)
                            if w >= h {
                                scaleY = s
                                scaleX = s * h / w
                            } else {
                                scaleX = s
                                scaleY = s * w / h
                            }
                            panX += CGFloat(Float(dx) * 2 / (w * scaleX * 0.01))
                            panY += CGFloat(Float(dy) * 2 / (h * scaleY * 0.01))
                            lastPan = CGSize(width: panX, height: panY)
                        } onPressEscape: {
                            appState.clearSelection()
                        } onMouseMove: { coords in
                            if let (x, y) = coords {
                                mouseSceneX = x
                                mouseSceneY = y
                            } else {
                                mouseSceneX = nil
                                mouseSceneY = nil
                            }
                        } onSelect: { node, link in
                            appState.setSelection(nodeIndex: node, linkIndex: link)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                        if appState.resultOverlayMode != .none {
                            ResultOverlayLegend(
                                mode: appState.resultOverlayMode,
                                nodeRange: nodeRange,
                                linkRange: linkRange,
                                offset: resultLegendOffset
                            )
                            .padding(14)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                            .gesture(
                                DragGesture()
                                    .onChanged { value in
                                        resultLegendOffset = CGSize(
                                            width: resultLegendLastOffset.width + value.translation.width,
                                            height: resultLegendLastOffset.height + value.translation.height
                                        )
                                    }
                                    .onEnded { _ in resultLegendLastOffset = resultLegendOffset }
                            )
                        }

                        if case .success(let elapsed) = appState.runResult {
                            MacRunToast(elapsed: elapsed)
                                .padding(.top, 14)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        }

                        VStack(spacing: 6) {
                            Button("+") {
                                scale = min(20, scale * 1.12)
                                lastScale = scale
                            }
                            .buttonStyle(.plain)
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))

                            Button("⊡") {
                                scale = 1
                                panX = 0
                                panY = 0
                                lastScale = 1
                                lastPan = .zero
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))

                            Button("−") {
                                scale = max(0.2, scale * 0.88)
                                lastScale = scale
                            }
                            .buttonStyle(.plain)
                            .frame(width: 30, height: 30)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                    if showRightPanel {
                        PropertyPanelView(appState: appState, selectedNodeIndex: appState.selectedNodeIndex, selectedLinkIndex: appState.selectedLinkIndex, onClose: {
                            appState.clearSelection()
                        })
                        .frame(width: 260)
                    }
                }
                    .gesture(
                        MagnificationGesture()
                            .onChanged { scale = lastScale * $0 }
                            .onEnded { _ in lastScale = scale }
                    )
                    .simultaneousGesture(
                        DragGesture()
                            .onChanged { v in panX = lastPan.width + v.translation.width; panY = lastPan.height + v.translation.height }
                            .onEnded { _ in lastPan = CGSize(width: panX, height: panY) }
                    )
                    .onTapGesture(count: 2) {
                        scale = 1; panX = 0; panY = 0
                        lastScale = 1; lastPan = .zero
                        appState.clearSelection()
                    }
                    .onChange(of: appState.errorFocusNodeIndex) { node in
                        guard let node = node else { return }
                        appState.setSelection(nodeIndex: node, linkIndex: nil)
                    }
                    .onChange(of: appState.errorFocusLinkIndex) { link in
                        guard let link = link else { return }
                        appState.setSelection(nodeIndex: nil, linkIndex: link)
                    }
                    .onChange(of: appState.focusSelectionToken) { _ in
                        focusOnCurrentSelection(in: scene)
                    }
            } else {
                #if os(macOS)
                StartupSplitView(appState: appState)
                #else
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "map")
                        .font(.system(size: 64))
                        .foregroundColor(.secondary)
                    Text("打开 .inp 管网文件以显示图形")
                        .font(.title2)
                        .foregroundColor(.secondary)
                    Button("打开文件") {
                        appState.openFile()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 8)
                    Spacer()
                }
                #endif
            }
            if appState.scene != nil {
                #if os(macOS)
                MacDesignStatusBar(
                    appState: appState,
                    scale: scale,
                    mouseSceneX: mouseSceneX,
                    mouseSceneY: mouseSceneY,
                    onTapRunResult: { showRunResultSheet = true }
                )
                #else
                HStack(spacing: 12) {
                    Text("X: \(mouseSceneX.map { String(format: "%.2f", $0) } ?? "—")")
                    Text("Y: \(mouseSceneY.map { String(format: "%.2f", $0) } ?? "—")")
                    Spacer()
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(AppColors.controlBackground)
                .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.3)), alignment: .top)
                #endif
            }
        }
    }

    #if os(macOS)
    private func updateMacWindowTitle() {
        DispatchQueue.main.async {
            NSApp.mainWindow?.title = ""
        }
    }
    #endif
}

#if os(macOS)
private struct StartupSplitView: View {
    @ObservedObject var appState: AppState

    private let columns = [
        GridItem(.adaptive(minimum: 210), spacing: 14)
    ]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 18) {
                Text("EPANET 3")
                    .font(.title2.weight(.semibold))
                Text("打开 .inp 文件开始工作")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Button {
                    appState.openFile()
                } label: {
                    Label("打开文件", systemImage: "folder.badge.plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)

                if let path = appState.filePath {
                    Text("最近路径")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(path)
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Spacer()
            }
            .padding(20)
            .frame(width: 260)
            .frame(maxHeight: .infinity, alignment: .topLeading)
            .background(AppColors.controlBackground)

            Divider()

            VStack(alignment: .leading, spacing: 12) {
                Text("近期打开")
                    .font(.headline)
                    .padding(.top, 16)
                    .padding(.horizontal, 16)
                if appState.recentFiles.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "square.grid.2x2")
                            .font(.system(size: 22))
                            .foregroundColor(.secondary)
                        Text("暂无近期文件")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(appState.recentFiles) { item in
                                Button {
                                    appState.openRecentFile(item)
                                } label: {
                                    RecentFileThumbnailCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 18)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(AppColors.windowBackground)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct RecentFileThumbnailCard: View {
    let item: RecentFileItem

    private var openedText: String {
        item.lastOpenedAt.formatted(.dateTime.month().day().hour().minute())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.blue.opacity(0.10))
                .overlay(
                    VStack(alignment: .leading, spacing: 5) {
                        Text(".inp")
                            .font(.caption2.monospaced())
                            .foregroundColor(.blue)
                        HStack(spacing: 10) {
                            Label("\(item.nodeCount ?? 0)", systemImage: "smallcircle.filled.circle")
                            Label("\(item.linkCount ?? 0)", systemImage: "line.diagonal")
                        }
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    }
                    .padding(10),
                    alignment: .topLeading
                )
                .frame(height: 92)

            Text(item.displayName)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            Text(openedText)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
            Text(item.path)
                .font(.caption2.monospaced())
                .foregroundColor(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct NetworkTypeSummary {
    var junctions: Int = 0
    var tanks: Int = 0
    var reservoirs: Int = 0
    var pipes: Int = 0
    var valves: Int = 0
    var pumps: Int = 0

    var nodeTotal: Int { junctions + tanks + reservoirs }
    var linkTotal: Int { pipes + valves + pumps }
}

private struct MacDesignToolbar: View {
    @ObservedObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 2) {
                toolButton("arrow.up.left.and.down.right.and.arrow.up.right.and.down.left", active: appState.editorMode == .browse) {
                    appState.setEditorMode(.browse)
                }
                toolButton("plus.circle.fill", active: appState.editorMode == .add, tint: .blue) {
                    appState.setEditorMode(.add)
                }
                toolButton("trash.fill", active: appState.editorMode == .delete, tint: .orange) {
                    appState.setEditorMode(.delete)
                }
            }
            .padding(2)
            .background(Color(NSColor(calibratedWhite: 0.93, alpha: 1)), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25), lineWidth: 1))

            Divider().frame(height: 24)

            Button {
                appState.clearSelection()
            } label: {
                Image(systemName: "arrow.uturn.backward")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Button {
                appState.requestFocusOnSelection()
            } label: {
                Image(systemName: "scope")
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)

            Divider().frame(height: 24)

            Picker("结果上图", selection: Binding(
                get: { appState.resultOverlayMode },
                set: { appState.setResultOverlayMode($0) }
            )) {
                Text("图例").tag(ResultOverlayMode.none)
                Text("压力").tag(ResultOverlayMode.pressure)
                Text("流量").tag(ResultOverlayMode.flow)
            }
            .pickerStyle(.segmented)
            .frame(width: 220)

            Button("标注") {}
                .buttonStyle(.plain)
                .foregroundColor(.secondary)

            Spacer()

            #if os(macOS)
            Button("参数") {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            }
            .buttonStyle(.plain)
            .foregroundColor(.secondary)
            #endif

            Button {
                appState.runCalculation()
            } label: {
                Label("运行计算", systemImage: "play.fill")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.borderedProminent)
            .disabled(appState.isRunning)
        }
        .font(.system(size: 13, weight: .medium))
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [Color(NSColor(calibratedWhite: 0.98, alpha: 1)), Color(NSColor(calibratedWhite: 0.95, alpha: 1))],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .bottom)
    }

    private func toolButton(_ icon: String, active: Bool, tint: Color = .primary, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .frame(width: 30, height: 26)
                .foregroundColor(active ? tint : .secondary)
                .background(active ? tint.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
    }
}

private struct MacDesignSidebar: View {
    @ObservedObject var appState: AppState

    private var counts: NetworkTypeSummary {
        guard let p = appState.project else { return NetworkTypeSummary() }
        var summary = NetworkTypeSummary()
        do {
            let nodeCount = try p.nodeCount()
            for i in 0..<nodeCount {
                switch try p.getNodeType(index: i) {
                case .junction: summary.junctions += 1
                case .tank: summary.tanks += 1
                case .reservoir: summary.reservoirs += 1
                }
            }
            let linkCount = try p.linkCount()
            for i in 0..<linkCount {
                switch try p.getLinkType(index: i) {
                case .pipe, .cvpipe: summary.pipes += 1
                case .pump: summary.pumps += 1
                default: summary.valves += 1
                }
            }
        } catch {
            return summary
        }
        return summary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("图层")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 6)

            MacTreeRow(title: "节点", count: counts.nodeTotal, icon: "circle.fill", tint: .blue, isActive: true)
            MacTreeRow(title: "Junction", count: counts.junctions, icon: "circle.fill", tint: .blue, depth: 1)
            MacTreeRow(title: "Tank", count: counts.tanks, icon: "square.fill", tint: .green, depth: 1)
            MacTreeRow(title: "Reservoir", count: counts.reservoirs, icon: "triangle.fill", tint: .purple, depth: 1)
            MacTreeRow(title: "管段", count: counts.linkTotal, icon: "line.diagonal", tint: .gray)
            MacTreeRow(title: "Pipe", count: counts.pipes, icon: "line.diagonal", tint: .gray, depth: 1)
            MacTreeRow(title: "Valve", count: counts.valves, icon: "plus.circle.fill", tint: .orange, depth: 1)
            MacTreeRow(title: "Pump", count: counts.pumps, icon: "arrow.trianglehead.clockwise", tint: .red, depth: 1)

            Divider().padding(.vertical, 8)

            Text("搜索")
                .font(.caption2.weight(.semibold))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 12)
                .padding(.bottom, 6)
            TextField("按 ID 或名称...", text: .constant(""))
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 12)
                .disabled(true)

            Spacer()
        }
        .overlay(Rectangle().frame(width: 1).foregroundColor(.secondary.opacity(0.2)), alignment: .trailing)
    }
}

private struct MacTreeRow: View {
    let title: String
    let count: Int
    let icon: String
    let tint: Color
    var isActive: Bool = false
    var depth: Int = 0

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tint)
            Text(title)
                .font(.system(size: 13))
            Spacer()
            Text("\(count)")
                .font(.system(.caption, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.leading, CGFloat(12 + depth * 14))
        .padding(.trailing, 12)
        .frame(height: 24)
        .background(isActive ? Color.blue.opacity(0.08) : .clear)
    }
}

private struct MacRunToast: View {
    let elapsed: TimeInterval

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 16, height: 16)
                .background(Circle().fill(Color.green))
            Text("计算完成 · 用时 \(String(format: "%.1f", elapsed)) s")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color.green)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.green.opacity(0.35), lineWidth: 1))
    }
}

private struct MacDesignStatusBar: View {
    @ObservedObject var appState: AppState
    let scale: CGFloat
    let mouseSceneX: Float?
    let mouseSceneY: Float?
    let onTapRunResult: () -> Void

    private var counts: NetworkTypeSummary {
        guard let p = appState.project else { return NetworkTypeSummary() }
        var summary = NetworkTypeSummary()
        do {
            let nodeCount = try p.nodeCount()
            for i in 0..<nodeCount {
                switch try p.getNodeType(index: i) {
                case .junction: summary.junctions += 1
                case .tank: summary.tanks += 1
                case .reservoir: summary.reservoirs += 1
                }
            }
            let linkCount = try p.linkCount()
            for i in 0..<linkCount {
                switch try p.getLinkType(index: i) {
                case .pipe, .cvpipe: summary.pipes += 1
                case .pump: summary.pumps += 1
                default: summary.valves += 1
                }
            }
        } catch {}
        return summary
    }

    var body: some View {
        HStack(spacing: 10) {
            Button(action: onTapRunResult) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(resultColor)
                        .frame(width: 6, height: 6)
                    Text(resultTitle)
                }
                .font(.caption.monospaced())
            }
            .buttonStyle(.plain)
            Divider().frame(height: 12)
            Text("节点 \(counts.nodeTotal)")
            Text("管段 \(counts.linkTotal)")
            Text("阀门 \(counts.valves)")
            Text("水泵 \(counts.pumps)")
            Divider().frame(height: 12)
            Text("Hazen-Williams · \(InpOptionsParser.isUSCustomary(flowUnits: appState.inpFlowUnits) ? "US" : "SI")")
            Spacer()
            Text("缩放 \(Int(scale * 100))%")
            Divider().frame(height: 12)
            Text("X \(mouseSceneX.map { String(format: "%.0f", $0) } ?? "—") · Y \(mouseSceneY.map { String(format: "%.0f", $0) } ?? "—")")
        }
        .font(.system(size: 11, design: .monospaced))
        .foregroundColor(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            LinearGradient(
                colors: [Color(NSColor(calibratedWhite: 0.95, alpha: 1)), Color(NSColor(calibratedWhite: 0.92, alpha: 1))],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(Rectangle().frame(height: 1).foregroundColor(.secondary.opacity(0.25)), alignment: .top)
    }

    private var resultColor: Color {
        if appState.isRunning { return .orange }
        guard let result = appState.runResult else { return .secondary }
        switch result {
        case .success: return .green
        case .failure: return .red
        }
    }

    private var resultTitle: String {
        if appState.isRunning { return "计算中" }
        guard let result = appState.runResult else { return "未计算" }
        switch result {
        case .success: return "计算完成"
        case .failure: return "计算失败"
        }
    }
}
#endif

private struct ResultOverlayLegend: View {
    let mode: ResultOverlayMode
    let nodeRange: (Float, Float)?
    let linkRange: (Float, Float)?
    let offset: CGSize

    var body: some View {
        let range = mode == .pressure ? nodeRange : linkRange
        VStack(alignment: .leading, spacing: 8) {
            Text(mode == .pressure ? "节点压力 (m)" : "管段流量")
                .font(.caption.weight(.semibold))
                .foregroundColor(.secondary)
            LinearGradient(colors: [.blue, .red], startPoint: .leading, endPoint: .trailing)
                .frame(width: 160, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            if let r = range {
                Text(String(format: "%.3f  ->  %.3f", r.0, r.1))
                    .font(.caption2.monospaced())
                    .foregroundColor(.secondary)
            } else {
                Text("暂无结果数据")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.2), lineWidth: 1))
        .offset(offset)
    }
}

private struct TriangleShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

// MARK: - 运行结果 sheet（成功/失败与耗时或错误信息，供查询查看）
private struct RunResultSheet: View {
    let result: RunResult?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("运行结果")
                    .font(.headline)
                Spacer()
                Button("关闭") { dismiss() }
                    #if os(macOS)
                    .keyboardShortcut(.cancelAction)
                    #endif
            }
            if let result = result {
                switch result {
                case .success(let elapsed):
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                        Text("计算成功，耗时 \(String(format: "%.2f", elapsed)) 秒")
                            .foregroundColor(.primary)
                    }
                case .failure(let message):
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.red)
                            Text("计算失败")
                                .foregroundColor(.primary)
                        }
                        Text(message)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            } else {
                Text("暂无运行结果")
                    .foregroundColor(.secondary)
            }
            Spacer()
        }
        .padding(20)
        .frame(minWidth: 320, minHeight: 160)
    }
}
