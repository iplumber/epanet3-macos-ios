# EPANET 3 macOS / iOS 项目总览

这个仓库是 EPANET 3.0 水力计算引擎在 macOS / iOS 上的移植与 GUI 工程根目录，核心 Swift 包和 Xcode 工程都在这里。

## 目录结构（关键部分）

- `EPANET3App/`
  - `Package.swift`：Swift Package，包含 EPANET3 引擎、Swift 桥接、Metal 渲染和 GUI 代码。
  - `README.md`：EPANET3App 包内部的更详细说明。
  - `PHASE_HANDOFF.md`：阶段交接与第三阶段范围说明。
  - `BUILD_IOS.md`：同一 Xcode 工程下同时运行 macOS / iOS App 的说明。
  - `EPANET3Xcode/EPANET3Xcode.xcodeproj`：现成的 Xcode 工程，内含 **EPANET3Mac**（macOS）和 **EPANET3iOS**（iOS/iPadOS）两个 target，引用上一级的 Swift 包。
- `epanet  resource/`：上游 EPANET 2.2 / 3.0 源码与算例，仅作为资源和参考。
- `docs/EPANET3_macOS_iOS_移植规划.md`：项目整体规划文档。

## 如何在本机打开和运行

### 方式一：用 Swift Package（命令行构建）

```bash
cd EPANET3App
swift build
```

构建完成后，可以运行包内的可执行文件（例如 GUI App 和 CLI），详细用法见 `EPANET3App/README.md`。

### 方式二：用 Xcode 工程（推荐）

1. 打开 Xcode。
2. 打开工程：`EPANET3App/EPANET3Xcode/EPANET3Xcode.xcodeproj`。
3. 在 Xcode 顶部选择 Scheme：
   - 选 **EPANET3Mac** → 选 **My Mac** → 运行：获得 macOS 版 GUI。
   - 选 **EPANET3iOS** → 选 iPhone / iPad 模拟器或真实设备 → 运行：获得 iOS / iPadOS 版 GUI。

两个 App 共用同一份 Swift 包代码（`EPANET3AppUI` 等），只需在包内修改一次，Mac 和 iOS 会一起更新。

## 上传到 GitHub 的建议

- 这个根目录（即当前 `README.md` 所在的位置）可以直接初始化为一个 Git 仓库。
- `.gitignore` 已配置，忽略：
  - macOS 系统文件（`.DS_Store`）
  - SwiftPM 的 `.build/`、`.swiftpm/xcode/`
  - Xcode 的 `DerivedData/`、`*.xcuserdata/` 等中间文件
  - 上游 EPANET 源码下的本地 build 目录

GitHub 上只需要新建一个**空仓库**，然后把本地代码推上去即可。

