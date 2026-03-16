# 在 iPad / Mac 上运行（同一工程、双 target）

**可以**在**同一个 Xcode 工程**里同时跑 **macOS App** 和 **iOS App**，不需要两个工程。做法是：一个工程、两个 target（一个 Mac、一个 iOS），**共享代码全部放在本仓库的 Swift 包里**，自然保持同步。

---

## 已提供现成 Xcode 工程（推荐）

仓库里已有一个可直接打开的 **Xcode 工程**，内含 Mac 与 iOS 两个 target，无需再手动建工程或加 target。

- **路径**：`EPANET3App/EPANET3Xcode/EPANET3Xcode.xcodeproj`
- **打开方式**：用 **Xcode** 打开上述 `.xcodeproj` 文件。
- **运行 Mac 版**：顶部 Scheme 选 **EPANET3Mac** → 选 **My Mac** 或任意 Mac → 点 Run（▶）。
- **运行 iOS / iPad 版**：Scheme 选 **EPANET3iOS** → 选你的 **iPad 设备**或模拟器 → 点 Run。

工程已通过 **本地 Swift 包** 引用上一级目录的 `Package.swift`（即 `EPANET3App` 包），两个 target 都依赖 **EPANET3AppUI**，共享代码只需在包内修改一处即可。

---

## 同一工程、双 target，代码如何同步？

| 内容 | 放在哪 | 说明 |
|------|--------|------|
| 界面与逻辑（ContentView、AppState、属性面板、单位解析等） | **Swift 包 EPANET3App**（本仓库） | 唯一一份，Mac 和 iOS 都通过依赖 **EPANET3AppUI** 使用 |
| 工程与入口 | **Xcode 工程** 里的两个 target | 每个 target 只需一个很小的 `@main` 文件，引用包里的界面 |

只要改代码时都改 **Swift 包里的文件**（在 Cursor 里改或 Xcode 里打开 Package 改），Mac 和 iOS 会一起用最新代码，无需手动同步。

---

## 做法一：先有 iOS 工程，再加 Mac target

1. 按下面「1. 新建 iOS 工程」「2. 添加本地的 Swift 包」「3. 改成用我们的界面」做完，保证 iOS 已经能跑。
2. **加 macOS target**：菜单 **File → New → Target…** → 选 **macOS** → **App** → **Next**，Product Name 填 `EPANET3Mac`，Interface 选 **SwiftUI**，**Finish**。
3. 在弹窗「Activate “EPANET3Mac” scheme?」里选 **Activate**。
4. 给 Mac target 加包：左侧点工程 → 选 **EPANET3Mac** target → **General** → **Frameworks, Libraries, and Embedded Content** → **+** → 选 **EPANET3AppUI**（若没有，先到 **Package Dependencies** 确认包已加，并把 EPANET3AppUI 勾选给 EPANET3Mac）。
5. 打开 Xcode 为 Mac 生成的 `EPANET3MacApp.swift`（或类似名），整份换成：

```swift
import SwiftUI
import EPANET3AppUI

@main
struct EPANET3MacApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("文件") {
                Button("打开 .inp 文件...") { appState.openFile() }
                    .keyboardShortcut("o", modifiers: .command)
            }
        }
    }
}
```

6. 顶部 **Scheme** 选 **EPANET3Mac** 可跑 Mac，选 **EPANET3iOS** 可跑 iOS/iPad；切换设备/模拟器即可分别调试。

---

## 做法二：先有 Mac 工程，再加 iOS target

1. **File → New → Project…** → 选 **macOS** → **App**，建好工程并保存到与 **EPANET3App** 同级的目录。
2. **Package Dependencies** → **Add Local…** → 选 **EPANET3App**，勾选 **EPANET3AppUI** 加到 Mac target。
3. 把默认的 `*App.swift` 换成上面「做法一」里 Mac 的那段 `EPANET3MacApp` 代码，保证 Mac 能跑。
4. **File → New → Target…** → 选 **iOS** → **App** → Product Name 填 `EPANET3iOS`，**Finish**。
5. 给 **EPANET3iOS** target 在 **Frameworks, Libraries, and Embedded Content** 里加上 **EPANET3AppUI**。
6. 打开 iOS 的 `*App.swift`，换成前面「3. 改成用我们的界面」里的 iOS 那段（无 `.commands`）。

之后同样是：**一个工程、两个 Scheme（EPANET3Mac / EPANET3iOS）**，共享代码只在 Swift 包里改一次即可。

---

## 在 iPad 上直接编译运行（接上 Mac 后）

按下面步骤在 Xcode 里建一个 iOS 工程（或在你已有的「同一工程」里选 iOS target），并选你的 iPad 为运行目标，即可安装运行。

## 1. 新建 iOS 工程

1. 打开 **Xcode**
2. 菜单 **File → New → Project…**
3. 选 **iOS**，模板选 **App**，点 **Next**
4. 填写：
   - **Product Name**：`EPANET3iOS`（或任意名）
   - **Team**：选你的 Apple ID / 开发团队
   - **Organization Identifier**：例如 `com.yourname`
   - **Interface**：**SwiftUI**
   - **Language**：**Swift**
   - 其它保持默认，**Next**
5. **Save** 时：**保存位置选在「包含 Package.swift 的 EPANET3App 文件夹的上一级」**  
   例如：若包在 `/Users/你/xcode-cursor/EPANET3App`，就选 `/Users/你/xcode-cursor`，这样工程和 EPANET3App 是同一层。

## 2. 添加本地的 Swift 包

1. 左侧点最上面蓝色 **工程图标**（EPANET3iOS）
2. 选 **Package Dependencies**
3. 点左下角 **+**
4. 点 **Add Local…**
5. 选中 **EPANET3App** 文件夹（里面有 `Package.swift` 的那一层），**Add Package**
6. 在弹窗里勾选 **EPANET3AppUI**，确保加到你的 **EPANET3iOS** target 上，**Add Package**

## 3. 改成用我们的界面

1. 在左侧文件列表里打开 **EPANET3iOSApp.swift**（或默认的 `*App.swift`）
2. **整份文件** 换成下面内容并保存：

```swift
import SwiftUI
import EPANET3AppUI

@main
struct EPANET3iOSApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
```

## 4. 选 iPad 并运行

1. 用 **USB 线** 把 iPad 接到 Mac，在 iPad 上如提示「要信任此电脑」请选 **信任**
2. 在 Xcode 顶部中间 **运行目标** 下拉框里，选你的 **iPad 设备名**（不要选模拟器）
3. 若提示 “Untrusted Developer”：在 iPad 上 **设置 → 通用 → VPN 与设备管理** 里信任你的开发者证书
4. 点 **Run（▶）** 或按 **⌘R**，Xcode 会编译并装到 iPad 上并启动

之后每次改完代码，只要再点 Run，就会重新装到已连接的 iPad 上。

---

## 小结

- **同一工程、两个 target（Mac + iOS）** 即可，不必两个工程。
- **共享代码**：全部在 **EPANET3App** 这个 Swift 包里（ContentView、AppState、单位、计算等）；Xcode 工程里只有两个很小的 `@main` 入口文件。
- **保持同步**：只维护包里的代码，Mac 和 iOS 都依赖同一份 **EPANET3AppUI**，改一处、两平台一起更新。
