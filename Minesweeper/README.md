## Minesweeper (SwiftUI 多平台示例)

这个文件夹包含一个基于 **Swift 5.9 + SwiftUI** 的 9x9 经典扫雷游戏（10 颗地雷），核心代码位于 `Shared` 目录，可用于 **iOS 16+ / iPadOS / macOS** 的多平台 App。

当前提供的是源码结构，你可以按如下步骤在 Xcode 中创建一个可直接运行的多平台工程：

1. 打开 Xcode，`File > New > Project...` 选择 **Multiplatform > App**。
2. Product Name 填写 `Minesweeper`，Interface 选择 **SwiftUI**，Language 选择 **Swift**，勾选 iOS 和 macOS。
3. 创建完成后，将 Xcode 自动生成的 `Shared` 目录下的 `ContentView.swift`、`MinesweeperApp.swift` 删除或替换为本项目 `Shared` 目录中的同名文件。
4. 如果有命名差异，确保 `@main` 的 `App` 结构体名称和文件在两个 Target（iOS、macOS）中都勾选为 Target Membership。
5. 选择 iOS Simulator 或 My Mac (Designed for iPad / Mac)，直接 Build & Run 即可体验游戏。

### 交互说明

- 单击 / 单指点按：翻开格子（首次点击保证不会踩雷）。
- 长按（iOS）/ 长按或右键菜单（macOS）：标记/取消标记红旗。
- 双击：在一个已翻开的数字格上，若周围旗子数等于该数字，将自动快速展开周围未标记格子。

