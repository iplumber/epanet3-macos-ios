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
    @State private var selectedNodeIndex: Int?
    @State private var selectedLinkIndex: Int?
    @State private var isPropertyPanelVisible = false
    @State private var mouseSceneX: Float?
    @State private var mouseSceneY: Float?
    @State private var showRunResultSheet = false

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
                    MetalNetworkView(scene: scene, scale: scale, panX: panX, panY: panY, selectedNodeIndex: selectedNodeIndex, selectedLinkIndex: selectedLinkIndex) { delta, viewPoint, viewSize in
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
                        selectedNodeIndex = nil
                        selectedLinkIndex = nil
                    } onMouseMove: { coords in
                        if let (x, y) = coords {
                            mouseSceneX = x
                            mouseSceneY = y
                        } else {
                            mouseSceneX = nil
                            mouseSceneY = nil
                        }
                    } onSelect: { node, link in
                        selectedNodeIndex = node
                        selectedLinkIndex = link
                        if node != nil || link != nil {
                            isPropertyPanelVisible = true
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    .background(Color(white: 0.95))
                    if isPropertyPanelVisible {
                        PropertyPanelView(appState: appState, selectedNodeIndex: selectedNodeIndex, selectedLinkIndex: selectedLinkIndex, onClose: {
                            selectedNodeIndex = nil
                            selectedLinkIndex = nil
                            isPropertyPanelVisible = false
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
                        selectedNodeIndex = nil
                        selectedLinkIndex = nil
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
