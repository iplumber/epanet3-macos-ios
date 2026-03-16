## iPad 扫雷（适配 iPad mini）

源码目录：`Minesweeper-iPad/Sources`

### 在 Xcode 中创建可运行工程（iPadOS 16+）

由于这里是纯源码交付，你只需要用 Xcode 创建一个 iOS SwiftUI App，然后把这些文件拖进去即可运行：

1. Xcode -> `File > New > Project...` -> **iOS > App**
2. Product Name：`MinesweeperiPad`（或任意）
3. Interface：**SwiftUI**，Language：**Swift**
4. Deployment Target：**iOS 16.0+**
5. 在新工程里删除默认的 `ContentView.swift` / `xxxApp.swift`（或保留但不要重复 `@main`）
6. 将本目录 `Sources` 下的 4 个文件拖入工程：
   - `MinesweeperiPadApp.swift`
   - `ContentView.swift`
   - `GameLogic.swift`
   - `UIKitGestures.swift`
   - `Haptics.swift`
7. 选择运行设备：`iPad mini` 模拟器，直接 `⌘R`

### 交互（iPad）

- 单指点按：翻开格子（首点不死）
- 单指长按：插旗/取消插旗
- 双击：快速展开（Chord）
- **两指长按**：快速展开（Chord）

### iPad mini 适配点

- 棋盘最大宽度限制为 520pt，格子大小限定在 32~56pt，避免在 iPad mini 上“过大”导致观感不协调。

