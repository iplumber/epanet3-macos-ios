import SwiftUI
import UniformTypeIdentifiers
import EPANET3Renderer
#if canImport(UIKit)
import UIKit
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
                    HStack(spacing: 8) {
                        Button {
                            appState.setEditorMode(.browse)
                        } label: {
                            Label("浏览", systemImage: "hand.tap")
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.editorMode == .browse ? .accentColor : .gray)

                        Button {
                            appState.setEditorMode(.add)
                        } label: {
                            Label("添加", systemImage: "plus.circle")
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.editorMode == .add ? .accentColor : .gray)

                        Button {
                            appState.setEditorMode(.delete)
                        } label: {
                            Label("删除", systemImage: "trash")
                        }
                        .buttonStyle(.bordered)
                        .tint(appState.editorMode == .delete ? .accentColor : .gray)

                        if appState.editorMode == .edit {
                            Text("编辑中")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else if appState.editorMode == .result {
                            Text("结果")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Picker("结果上图", selection: Binding(
                            get: { appState.resultOverlayMode },
                            set: { appState.setResultOverlayMode($0) }
                        )) {
                            Text("无").tag(ResultOverlayMode.none)
                            Text("压力").tag(ResultOverlayMode.pressure)
                            Text("流量").tag(ResultOverlayMode.flow)
                        }
                        .pickerStyle(.segmented)
                        .frame(maxWidth: 260)

                        Button {
                            appState.runCalculation()
                        } label: {
                            Image(systemName: "play.fill")
                                .font(.system(size: 14, weight: .medium))
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .background(Color.accentColor)
                        .foregroundColor(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .disabled(appState.isRunning)
                        if appState.isRunning {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("计算中…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppColors.controlBackground)
                }
                ZStack(alignment: .trailing) {
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
                        linkScalarRange: appState.resultOverlayMode == .flow ? linkRange : nil
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
                    .background(Color(white: 0.95))
                    if appState.isPropertyPanelVisible {
                        PropertyPanelView(appState: appState, selectedNodeIndex: appState.selectedNodeIndex, selectedLinkIndex: appState.selectedLinkIndex, onClose: {
                            appState.clearSelection()
                        })
                        .frame(width: 260)
                    }
                    if appState.resultOverlayMode != .none {
                        ResultLegendView(mode: appState.resultOverlayMode, nodeRange: nodeRange, linkRange: linkRange)
                            .padding(12)
                            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
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
                    .onChange(of: appState.errorFocusNodeIndex) { newNode in
                        guard let node = newNode else { return }
                        appState.setSelection(nodeIndex: node, linkIndex: nil)
                    }
                    .onChange(of: appState.errorFocusLinkIndex) { newLink in
                        guard let link = newLink else { return }
                        appState.setSelection(nodeIndex: nil, linkIndex: link)
                    }
                    .onChange(of: appState.focusSelectionToken) { _ in
                        focusOnCurrentSelection(in: scene)
                    }
            } else {
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
            }
            if appState.scene != nil {
                HStack(spacing: 12) {
                    if let result = appState.runResult {
                        Button {
                            showRunResultSheet = true
                        } label: {
                            switch result {
                            case .success:
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                            case .failure:
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.red)
                            }
                        }
                        .buttonStyle(.plain)
                    }
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
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("打开") { appState.openFile() }
            }
        }
        .fileImporter(isPresented: $appState.showFileImporter, allowedContentTypes: [UTType(filenameExtension: "inp") ?? .plainText], allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            _ = url.startAccessingSecurityScopedResource()
            appState.openFileFromURL(url)
        }
        #endif
        .sheet(isPresented: $showRunResultSheet) {
            RunResultSheet(result: appState.runResult)
        }
    }
}

private struct ResultLegendView: View {
    let mode: ResultOverlayMode
    let nodeRange: (Float, Float)?
    let linkRange: (Float, Float)?

    var body: some View {
        let range = mode == .pressure ? nodeRange : linkRange
        VStack(alignment: .leading, spacing: 6) {
            Text(mode == .pressure ? "压力上图" : "流量上图")
                .font(.caption.weight(.semibold))
            LinearGradient(colors: [.blue, .red], startPoint: .leading, endPoint: .trailing)
                .frame(width: 140, height: 10)
                .clipShape(RoundedRectangle(cornerRadius: 4))
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
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 8))
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
