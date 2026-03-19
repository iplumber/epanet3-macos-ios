# EPANET3 macOS / iOS - 当前状态与下一步

本文件用于在任何电脑 / 新对话中快速了解进度，请在开始前先阅读本文件 + `README.md` + `PHASE_HANDOFF.md` + `../docs/开发任务清单_v1.md` + `../docs/验收标准_v1.md`。

---

## 一、当前整体状态（简要）

- **工程托管位置**：`https://github.com/iplumber/epanet3-macos-ios.git`
- **主工作目录**：仓库内的 `EPANET3App/`（Swift Package + Xcode 工程）。
- **平台支持**：macOS 13+、iOS 16+，同一工程下已有 **Mac + iOS 双 target**：
  - Xcode 工程：`EPANET3App/EPANET3Xcode/EPANET3Xcode.xcodeproj`
  - Target：
    - `EPANET3Mac`（macOS App）
    - `EPANET3iOS`（iOS / iPadOS App）
- **共享代码结构**（见 `Package.swift` 与 `README.md`）：
  - `EPANET3`：EPANET 3 C++ 引擎（源码已集成在 `EPANET3App/EPANET3/`，源自 OpenWaterAnalytics/epanet-dev）。
  - `EPANET3Bridge`：Swift Bridge，封装 EPANET API。
  - `EPANET3Renderer`：Metal 渲染（水力网络、缩放平移、点击命中等）。
  - `EPANET3AppUI`：SwiftUI 界面与应用状态（ContentView、AppState、属性面板、单位解析、计算运行、结果展示等）。
  - `EPANET3App`：可执行 target（命令行 / 旧入口），Xcode 工程内的 Mac / iOS 入口是另外的 `@main` App 文件。

---

## 二、功能完成度（高层）

- **已完成 / 可用**
  - `.inp` 文件加载（通过 Swift Bridge 调用 EPANET3 引擎）。
  - Metal 渲染网络图（节点 / 管段，缩放、平移、视图重置）。
  - 击中测试和选择逻辑（像素级容差、点优先于线、误点控制）。
  - 运行水力计算（基于内存 Project / Solver，非一次性 `runEpanet`）：
    - 运行时 UI：三角形“播放”按钮、运行中状态。
    - 运行结果反馈：成功 / 失败弹窗 + 耗时，状态栏成功 / 失败图标。
  - 结果读取：节点压力 / 水头、管段流速 / 流量等，从同一内存 Project 读取。
  - 单位解析与显示：
    - 解析 `.inp` 中 flow units（GPM、CMD 等），区分美制 / 公制。
    - 属性面板按单位显示合适的标签（ft/psi/in 或 m/m³/d 等）。
  - iOS 适配：
    - 文件导入（`.fileImporter` + 安全作用域）。
    - `MetalNetworkView` iOS 版本（触控点击命中、缩放 / 平移绑定 SwiftUI 手势）。
    - 工具栏“打开”按钮。
  - **同一工程双 target**：
    - Mac / iOS 共用 `EPANET3AppUI` 的界面与逻辑。
    - Xcode 工程仅包含两个很薄的 `@main` App 文件。

- **仓库中已有的重要文档**
  - `EPANET3App/README.md`：包结构、构建与运行说明。
  - `EPANET3App/PHASE_HANDOFF.md`：阶段交接（v1 已完成版）。
  - `docs/EPANET3_macOS_iOS_移植规划.md`：整体规划。
  - `docs/开发任务清单_v1.md`：阶段任务与执行记录（最新）。
  - `docs/验收标准_v1.md`：验收标准与 E3 回归清单入口。
  - `docs/发布说明_v1.md`：v1 版本发布说明（对外/归档可复用）。
  - `docs/最终验收记录_v1.md`：v1 最终验收记录（归档基线）。

---

## 三、典型使用路径（验证工程是否正常）

1. **SwiftPM 构建（命令行）**
   ```bash
   cd EPANET3App
   swift build
   ```

2. **Xcode 下运行 Mac / iOS 版**
   1. 打开 `EPANET3App/EPANET3Xcode/EPANET3Xcode.xcodeproj`。
   2. 选 Scheme：
      - `EPANET3Mac` → 设备选 “My Mac” → Run。
      - `EPANET3iOS` → 选 iPhone / iPad 或真实设备 → Run。
   3. 在 App 中通过“打开 .inp 文件”加载算例，验证：
      - 网络图渲染正常。
      - 节点 / 管段点击选择准确。
      - 运行计算能结束并显示结果（耗时 / 状态）。
      - 属性面板中的压力 / 流速 / 单位显示正确。

3. **算例文件（已纳入仓库）**
   - `epanet  resource/example/Epanet 管网/net1.inp`
   - `epanet  resource/example/Epanet 管网/any1.inp`
   - `epanet  resource/example/可计算 算例管网 inp/400.inp`
   - `epanet  resource/example/可计算 算例管网 inp/10000.inp`
   - `epanet  resource/example/可计算 算例管网 inp/90000.inp`
   - 未纳入：`490000.inp`（过大，按需自行保留在本地但不进 Git）。

---

## 四、阶段完成度（截至当前）

- A：已完成（范围冻结，仅 `.inp`）
- B：已完成（引擎与桥接能力补齐，错误标准化到对象级上下文）
- C：已完成（状态机、ID 选中模型、模型变更到场景刷新链路）
- D：已完成（属性编辑、对象增删、参数设置、结果上图最小集）
- E：已完成（E1/E2/E3，含 CLI 回归与 UI 稳定性回归清单）

说明：
- 三算例 `net1.inp` / `any1.inp` / `400.inp` 已通过回归。
- `10000.inp` 与 `90000.inp` 已完成 release 性能与稳定性检查。

---

## 五、下一步推荐工作（收尾与发布）

1. **发布前文档归档**
   - 阶段验收结论已补齐（见 `docs/验收标准_v1.md` 第 7 节）。
   - 更新对外 README（如需新增“已知限制”）。

2. **打包与版本管理**
   - 建议创建 `v1` 发布分支或 tag。
   - 在变更日志中记录 D/E 阶段主要能力与已知限制。

3. **可选增强（v1.x / v2）**
   - 结果上图扩展（更多指标、时间步结果浏览）。
   - 大图性能进一步优化（> 90k 节点/管段）。
   - iOS 小屏交互与布局细化。

---

## 六、新对话如何快速接管

在任意新电脑 / 新对话中，请按以下顺序操作并告知助手：

1. `git clone https://github.com/iplumber/epanet3-macos-ios.git`
2. 在 Cursor / IDE 中打开仓库根目录。
3. 明确说明：「请先阅读 `EPANET3App/STATUS.md`、`EPANET3App/README.md`、`EPANET3App/PHASE_HANDOFF.md`、`EPANET3App/BUILD_IOS.md`，然后继续后续工作」。

这样助手可以在无需完整复盘历史对话的情况下，直接基于当前工程状态继续推进后续开发与调试。

