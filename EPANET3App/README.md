# EPANET 3 macOS/iOS 移植 - 引擎与 Swift 桥接

## v1 发布状态
- v1 主线阶段 A/B/C/D/E 已完成。
- 当前建议：先做发布归档，再进入 v1.x 的界面强化与能力增强。

阶段交接与当前状态见 [PHASE_HANDOFF.md](PHASE_HANDOFF.md) 与 [STATUS.md](STATUS.md)。
发布口径与验收归档见 [../docs/发布说明_v1.md](../docs/发布说明_v1.md) 与 [../docs/最终验收记录_v1.md](../docs/最终验收记录_v1.md)。

本包将 EPANET 3.0 水力计算引擎集成到 Swift，支持 macOS 和 iOS。

### 结构

- **EPANET3**：EPANET 3 C++ 引擎（源码已集成在 `EPANET3App/EPANET3/`，源自 OpenWaterAnalytics/epanet-dev）
- **EPANET3Bridge**：Swift 封装，暴露 `EpanetProject`、`runEpanet`、`getNodeCoords` 等 API
- **EPANET3Renderer**：Metal 渲染管线，绘制管段（线段）和节点（点），支持缩放、平移
- **EPANET3CLI**：命令行测试工具，用于验证引擎与桥接
- **EPANET3App**：图形应用入口（Xcode 中运行 `EPANET3Mac` / `EPANET3iOS`）

### 构建

```bash
cd EPANET3App
swift build
```

### 运行 GUI 应用（推荐用 Xcode）

1. 打开 `EPANET3Xcode/EPANET3Xcode.xcodeproj`
2. 选择 Scheme：
   - `EPANET3Mac`（macOS）
   - `EPANET3iOS`（iOS / iPadOS）
3. 运行后通过“打开 .inp 文件”加载管网

### 运行 GUI 应用（命令行调试）

```bash
.build/debug/EPANET3App
# 通过 文件 > 打开 .inp 文件 加载管网，支持双指/滚轮缩放、拖拽平移、双击重置视图
```

### 运行 CLI 测试

```bash
# 使用 net1.inp（11 节点，13 管段）
.build/debug/EPANET3CLI "../epanet  resource/example/Epanet 管网/net1.inp"

# 使用 any1.inp（25 节点，43 管段）
.build/debug/EPANET3CLI "../epanet  resource/example/Epanet 管网/any1.inp"

# 指定报告与输出路径
.build/debug/EPANET3CLI <inp_path> [rpt_path] [out_path]
```

### 格式支持

仅支持 `.inp` 文本格式，不支持 `.net` 二进制格式。

### v1 已交付能力（最小集）
- 文件流程：打开、编辑、保存/另存 `.inp`
- 对象流程：节点/管段核心属性编辑，新增/删除（含按 ID 删除）
- 计算流程：运行计算，成功/失败反馈
- 结果流程：压力/流量结果上图与图例显示
- 参数流程：计算参数编辑，Flow Units `GPM/LPS` 重载切换
- 错误流程：错误码 + 文本 + 对象级上下文，可用于定位

### v1 已知限制
- Flow Units 切换当前采用临时副本重载策略。
- 结果上图目前是最小集（压力/流量）。
- iOS 小屏交互仍建议在 v1.x 继续优化。

### 使用示例

```swift
import EPANET3Bridge

// 方式一：一次性运行（等同于 run-epanet3）
try runEpanet(inpPath: "net1.inp", rptPath: "report.txt", outPath: "output.bin")

// 方式二：Project API（分步控制）
let project = EpanetProject()
try project.load(path: "net1.inp")
let nodeCount = try project.nodeCount()
let linkCount = try project.linkCount()
try project.initSolver(initFlows: false)
var t: Int32 = 0
repeat {
    try project.runSolver(time: &t)
    var dt: Int32 = 0
    try project.advanceSolver(dt: &dt)
} while t > 0
let pressure = try project.getNodeValue(nodeIndex: 1, param: .pressure)
```
