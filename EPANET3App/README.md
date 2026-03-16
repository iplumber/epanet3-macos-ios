# EPANET 3 macOS/iOS 移植 - 引擎与 Swift 桥接

## 第一阶段：引擎移植 + Swift 桥接（已完成）
## 第二阶段：Metal 渲染与地图视图（已完成）
## 第三阶段：运行计算与结果查看（待开展）

阶段交接与第三阶段范围见 [PHASE_HANDOFF.md](PHASE_HANDOFF.md)。

本包将 EPANET 3.0 水力计算引擎集成到 Swift，支持 macOS 和 iOS。

### 结构

- **EPANET3**：EPANET 3 C++ 引擎（通过符号链接引用 `epanet  resource/epanet-dev-develop/src`）
- **EPANET3Bridge**：Swift 封装，暴露 `EpanetProject`、`runEpanet`、`getNodeCoords` 等 API
- **EPANET3Renderer**：Metal 渲染管线，绘制管段（线段）和节点（点），支持缩放、平移
- **EPANET3CLI**：命令行测试工具，用于验证引擎与桥接
- **EPANET3App**：macOS 图形应用，打开 .inp 文件并显示管网图

### 构建

```bash
cd EPANET3App
swift build
```

### 运行 GUI 应用

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
