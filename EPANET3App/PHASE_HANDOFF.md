# 阶段交接说明

## 第二阶段完成情况（已交付）

### 1. Metal 渲染与地图视图
- **EPANET3Renderer**：Metal 管线绘制管段（线段）和节点（点）；支持双指/滚轮缩放、左键拖拽平移、双击重置视图；宽高比修正，侧边栏开关时地图不拉伸。
- **MetalNetworkView**（SwiftUI）：封装 `ScrollableContainerView` + `MapMTKView`，接收 `scene`（节点/管段几何）、`onSelectNode`/`onSelectLink` 等回调。

### 2. 场景坐标与交互
- **MetalNetworkCoordinator**：
  - `viewToScene(viewPoint:viewSize:) -> (Float, Float)?`：将视图坐标转换为场景（管网）坐标，与 hitTest 使用相同 scale/pan 与宽高比修正；无场景时返回 `nil`。
- **MapMTKView**：
  - `updateTrackingAreas()` 中注册 `NSTrackingArea`（`.mouseMoved`、`.mouseEnteredAndExited`、`.activeInKeyWindow`）。
  - `mouseMoved(with:)`、`mouseExited(with:)` 转发给 `eventHandler` 的 `handleMouseMoved` / `handleMouseExited`。
- **ScrollableContainerView**：
  - `onMouseMove: (((Float, Float)?) -> Void)?`；`handleMouseMoved` 用 coordinator 的 `viewToScene` 得到场景坐标后调用 `onMouseMove?((sx, sy))`，`handleMouseExited` 时调用 `onMouseMove?(nil)`。
- **MetalNetworkView** 对外暴露 `onMouseMove`，在 `makeNSView`/`updateNSView` 中赋给 container。

### 3. 底部状态栏
- **ContentView**：
  - `@State mouseSceneX`、`mouseSceneY`（`Float?`），通过 `onMouseMove` 更新。
  - 当 `appState.scene != nil` 时，在窗口底部显示一条状态栏：`X: xx.xx`、`Y: xx.xx`（两位小数），无坐标时显示 `—`；样式为等宽字体、次要色、控件背景、顶部分隔线。

### 关键文件
| 功能 | 文件路径 |
|------|----------|
| 渲染、坐标转换、鼠标事件 | `EPANET3Renderer/Sources/EPANET3Renderer/MetalNetworkView.swift` |
| 主界面、状态栏、场景绑定 | `EPANET3App/ContentView.swift` |
| 应用状态（scene、选中节点/管段等） | 见 ContentView 及 appState 相关类型 |

### 构建与运行
```bash
cd EPANET3App
swift build
.build/debug/EPANET3App
```
- 通过 **文件 > 打开** 加载 `.inp` 文件后，可缩放/平移、点击选节点/管段，底部状态栏显示鼠标所在场景 XY 坐标。

---

## 第三阶段目标：运行计算与结果查看

- **运行计算**：在现有“加载 .inp + 显示管网图”基础上，增加“运行水力计算”的能力（可复用 EPANET3Bridge 的 `runEpanet` 或 `EpanetProject` 分步 API），并在 UI 上触发（如菜单或按钮）。
- **结果查看**：计算完成后，能够查看并展示结果数据，例如：
  - 节点：压力、水头、需求等；
  - 管段：流量、流速、水头损失等；
  - 可选：按时间步查看、在图上用颜色/标注显示某一结果量。

新对话可直接基于本仓库当前代码，从“运行计算”入口与“结果数据结构/展示方式”开始设计第三阶段实现。

---

## 第五阶段：iOS 适配（已开展，目标 iPad mini A17 / iPhone 15 Pro）

### 已完成
- **平台条件编译**：`EPANET3App.swift` 仅 macOS 使用 `.frame(minWidth/minHeight)` 与 `.commands`；iOS 无菜单，依赖工具栏与 .fileImporter。
- **打开文件**：macOS 仍用 `NSOpenPanel`；iOS 使用 `showFileImporter` + `.fileImporter(isPresented:allowedContentTypes:...)`，选档后 `startAccessingSecurityScopedResource()` 并 `openFileFromURL(_:)` 加载。
- **跨平台颜色**：`ContentView` 使用 `AppColors.controlBackground` / `AppColors.windowBackground`（macOS→NSColor，iOS→UIColor）；`PropertyPanelView` 使用 `platformWindowBackgroundColor`。
- **MetalNetworkView（iOS）**：与 macOS 同参数（scene, scale, panX, panY, selectedNodeIndex, selectedLinkIndex, onSelect 等）；`makeUIView` 中为 MTKView 添加 `UITapGestureRecognizer`，在 `MetalNetworkCoordinator.handleTap(_:)` 中做 hitTest 并回调 `onSelect`；`updateUIView` 同步 scene/scale/pan/选中态，缩放与平移继续由 ContentView 的 SwiftUI `MagnificationGesture` / `DragGesture` 提供。
- **工具栏**：iOS 使用 `.toolbar { ToolbarItem(placement: .primaryAction) { Button("打开") ... } }` 提供打开入口。
- **RunResultSheet**：`.keyboardShortcut(.cancelAction)` 仅限 macOS。

### 在 Xcode 中跑 iOS
- 当前为 Swift Package，可执行目标默认以 macOS 为主。在 **iPad mini (A17)**、**iPhone 15 Pro** 上运行需在 Xcode 中新建 **iOS App** 工程，将本 Package 作为依赖引入，或把 `EPANET3App` 下源码加入 App target，并设置最低版本 iOS 16（与 Package 的 `.iOS(.v16)` 一致）。
- 设备/模拟器选择 iPad mini 或 iPhone 15 Pro，构建并运行即可验证触控、缩放、平移与点选。
