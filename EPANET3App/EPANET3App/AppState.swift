import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif
import UniformTypeIdentifiers
import EPANET3Bridge
import EPANET3Renderer

/// 最近一次运行计算的结果，供界面与后续查询展示。
enum RunResult: Equatable {
    case success(elapsed: TimeInterval)
    case failure(message: String)
}

@MainActor
public final class AppState: ObservableObject {
    @Published var scene: NetworkScene?
    @Published var project: EpanetProject?
    @Published var filePath: String?
    @Published var errorMessage: String?
    @Published var isLoading = false
    /// 最近一次运行计算的结果；nil 表示尚未运行或已清除。
    @Published var runResult: RunResult?
    @Published var isRunning = false
    /// 从当前 .inp 的 [OPTIONS] 解析的 Flow Units（如 "GPM", "LPS"），用于属性面板单位标签；nil 表示未解析或非 project 模式。
    @Published var inpFlowUnits: String?
    /// iOS：为 true 时弹出文件选择（.fileImporter）
    @Published var showFileImporter = false

    public init() {}

    public func openFile() {
        #if os(macOS)
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "inp") ?? .plainText]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "选择 .inp 管网文件"
        panel.message = "仅支持 .inp 格式"
        if panel.runModal() == .OK, let url = panel.url {
            load(path: url.path)
        }
        NSCursor.arrow.set()
        #else
        showFileImporter = true
        #endif
    }

    /// 从已选 URL 加载（iOS 在 fileImporter 回调中调用，需先 startAccessingSecurityScopedResource）
    public func openFileFromURL(_ url: URL) {
        load(path: url.path)
    }

    func load(path: String) {
        isLoading = true
        errorMessage = nil
        Task.detached(priority: .userInitiated) {
            do {
                let proj = EpanetProject()
                try proj.load(path: path)
                let scene = try Self.buildScene(from: proj)
                let flowUnits = InpOptionsParser.parseFlowUnits(path: path)
                await MainActor.run { [weak self] in
                    self?.project = proj
                    self?.scene = scene
                    self?.filePath = path
                    self?.errorMessage = nil
                    self?.inpFlowUnits = flowUnits
                    self?.isLoading = false
                }
            } catch EpanetError.apiError(200) {
                do {
                    let scene = try InpDisplayParser.parse(path: path)
                    await MainActor.run { [weak self] in
                        self?.project = nil
                        self?.scene = scene
                        self?.filePath = path
                        self?.errorMessage = "仅显示模式（不可计算）"
                        self?.inpFlowUnits = InpOptionsParser.parseFlowUnits(path: path)
                        self?.isLoading = false
                    }
                } catch {
                    await MainActor.run { [weak self] in
                        self?.errorMessage = "加载失败（仅显示解析）: \(error)"
                        self?.scene = nil
                        self?.project = nil
                        self?.filePath = nil
                        self?.inpFlowUnits = nil
                        self?.isLoading = false
                    }
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.errorMessage = "加载失败: \(error)"
                    self?.scene = nil
                    self?.project = nil
                    self?.filePath = nil
                    self?.inpFlowUnits = nil
                    self?.isLoading = false
                }
            }
        }
    }

    /// 使用当前打开的 .inp 在内存中的 project 上执行水力求解，结果保留在 project 中，属性面板的压力/水头/流量/流速会正确显示。
    func runCalculation() {
        guard let path = filePath, !path.isEmpty else { return }
        isRunning = true
        runResult = nil
        let inpPath = path

        Task.detached(priority: .userInitiated) {
            let start = CFAbsoluteTimeGetCurrent()
            do {
                let proj = EpanetProject()
                try proj.load(path: inpPath)
                try proj.initSolver(initFlows: false)
                var t: Int32 = 0
                repeat {
                    try proj.runSolver(time: &t)
                    var dt: Int32 = 0
                    try proj.advanceSolver(dt: &dt)
                } while t > 0
                let elapsed = CFAbsoluteTimeGetCurrent() - start
                await MainActor.run { [weak self] in
                    self?.project = proj
                    self?.runResult = .success(elapsed: elapsed)
                    self?.isRunning = false
                }
            } catch EpanetError.apiError(let code) {
                let message = "EPANET 错误 (代码 \(code))"
                await MainActor.run { [weak self] in
                    self?.runResult = .failure(message: message)
                    self?.isRunning = false
                }
            } catch {
                await MainActor.run { [weak self] in
                    self?.runResult = .failure(message: String(describing: error))
                    self?.isRunning = false
                }
            }
        }
    }

    private static nonisolated func buildScene(from proj: EpanetProject) throws -> NetworkScene {
        let nodeCount = try proj.nodeCount()
        let linkCount = try proj.linkCount()

        var nodes: [NodeVertex] = []
        for i in 0..<nodeCount {
            let (x, y) = try proj.getNodeCoords(nodeIndex: i)
            if x > -1e19 && y > -1e19 {
                nodes.append(NodeVertex(x: Float(x), y: Float(y), nodeIndex: i))
            }
        }

        var links: [LinkVertex] = []
        for i in 0..<linkCount {
            let (n1, n2) = try proj.getLinkNodes(linkIndex: i)
            guard n1 >= 0, n2 >= 0, n1 < nodeCount, n2 < nodeCount else { continue }
            let (x1, y1) = try proj.getNodeCoords(nodeIndex: n1)
            let (x2, y2) = try proj.getNodeCoords(nodeIndex: n2)
            if x1 > -1e19, y1 > -1e19, x2 > -1e19, y2 > -1e19 {
                links.append(LinkVertex(x1: Float(x1), y1: Float(y1), x2: Float(x2), y2: Float(y2), linkIndex: i))
            }
        }

        if nodes.isEmpty && links.isEmpty {
            throw EpanetError.apiError(-1)
        }

        if nodes.isEmpty {
            nodes = [NodeVertex(x: 0, y: 0, nodeIndex: 0)]
        }

        return NetworkScene(nodes: nodes, links: links)
    }
}
