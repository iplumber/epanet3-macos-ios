/* DesignTokens — 与 UI/epanet-macos-light.html、epanet-macos.html 设计稿一致的像素级规范 */

import SwiftUI

#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// 设计稿颜色变量（浅色主题）
enum DesignColors {
    // Light (epanet-macos-light.html)
    static let lightBg = Color(red: 245/255.0, green: 244/255.0, blue: 240/255.0)           // #f5f4f0
    static let lightSurface = Color.white
    static let lightSurface2 = Color(red: 240/255.0, green: 239/255.0, blue: 233/255.0)     // #f0efe9
    static let lightSurface3 = Color(red: 232/255.0, green: 231/255.0, blue: 224/255.0)     // #e8e7e0
    static let lightBorder = Color(red: 221/255.0, green: 220/255.0, blue: 213/255.0)      // #dddcd5
    static let lightBorder2 = Color(red: 200/255.0, green: 199/255.0, blue: 190/255.0)    // #c8c7be
    static let lightText = Color(red: 26/255.0, green: 26/255.0, blue: 24/255.0)            // #1a1a18
    static let lightText2 = Color(red: 90/255.0, green: 90/255.0, blue: 86/255.0)          // #5a5a56
    static let lightText3 = Color(red: 154/255.0, green: 154/255.0, blue: 148/255.0)        // #9a9a94
    static let lightAccent = Color(red: 26/255.0, green: 111/255.0, blue: 232/255.0)       // #1a6fe8
    static let lightAccent2 = Color(red: 21/255.0, green: 88/255.0, blue: 192/255.0)       // #1558c0（主按钮描边/悬停）
    static let lightSuccess = Color(red: 26/255.0, green: 143/255.0, blue: 62/255.0)       // #1a8f3e
    static let lightWarn = Color(red: 184/255.0, green: 104/255.0, blue: 0)              // #b86800
    static let lightDanger = Color(red: 200/255.0, green: 53/255.0, blue: 42/255.0)       // #c8352a

    // Canvas (light)
    static let lightCanvasBg = Color(red: 248/255.0, green: 247/255.0, blue: 242/255.0)     // #f8f7f2
    static let lightCanvasGrid = Color(red: 221/255.0, green: 220/255.0, blue: 213/255.0)   // #dddcd5, opacity 0.5

    // Dark (epanet-macos.html)
    static let darkBg = Color(red: 30/255.0, green: 30/255.0, blue: 30/255.0)               // #1e1e1e
    static let darkSurface = Color(red: 37/255.0, green: 37/255.0, blue: 37/255.0)          // #252525
    static let darkSurface2 = Color(red: 44/255.0, green: 44/255.0, blue: 44/255.0)         // #2c2c2c
    static let darkSurface3 = Color(red: 51/255.0, green: 51/255.0, blue: 51/255.0)        // #333
    static let darkBorder = Color(red: 58/255.0, green: 58/255.0, blue: 58/255.0)            // #3a3a3a
    static let darkText = Color(red: 232/255.0, green: 232/255.0, blue: 230/255.0)          // #e8e8e6
    static let darkText2 = Color(red: 160/255.0, green: 160/255.0, blue: 158/255.0)        // #a0a09e
    static let darkText3 = Color(red: 104/255.0, green: 104/255.0, blue: 102/255.0)        // #686866
    static let darkAccent = Color(red: 74/255.0, green: 158/255.0, blue: 255/255.0)         // #4a9eff

    static let darkCanvasBg = Color(red: 26/255.0, green: 26/255.0, blue: 26/255.0)        // #1a1a1a
    static let darkCanvasGrid = Color(red: 44/255.0, green: 44/255.0, blue: 44/255.0)       // #2c2c2c, opacity 0.35
}

/// 拓扑编辑「开启」时菜单/控件强调色（偏紫红/洋红，区别于水泵红、阀门橙、水库蓝紫）。
public enum TopologyEditingAccent {
    /// sRGB 约 #A83076：紫红为主，避免与泵管（偏红）、阀门（偏橙）混淆。
    public static let menuOnTint = Color(red: 168/255, green: 48/255, blue: 118/255)
}

/// 设计稿字体规范
enum DesignFonts {
    static let fieldLabel: Font = .system(size: 11, weight: .medium)
    static let fieldName: Font = .system(size: 12)
    static let fieldValue: Font = .system(size: 12, design: .monospaced)
    static let tabLabel: Font = .system(size: 12)
    static let toolbarBtn: Font = .system(size: 13)
    static let sidebarSection: Font = .system(size: 11, weight: .medium)
    static let sidebarItem: Font = .system(size: 13)
    static let statusBar: Font = .system(size: 11, design: .monospaced)
    static let legendTitle: Font = .system(size: 11, weight: .medium)
    static let legendItem: Font = .system(size: 11)
}

/// 设计稿尺寸
enum DesignSizes {
    static let fieldValMinWidth: CGFloat = 72
    static let fieldValPaddingH: CGFloat = 8
    static let fieldValPaddingV: CGFloat = 3
    static let fieldValCornerRadius: CGFloat = 5
    static let fieldGroupMarginBottom: CGFloat = 16
    static let fieldRowMarginBottom: CGFloat = 6
    static let inspectorPaddingH: CGFloat = 14
    static let inspectorPaddingV: CGFloat = 12
    static let tabHeight: CGFloat = 26
    static let tabCornerRadius: CGFloat = 6
    static let canvasGridSize: CGFloat = 40
    static let canvasGridLineWidth: CGFloat = 1
}

/// 设计稿表面背景（侧边栏、检查器等）
struct DesignSurfaceBackground: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        (colorScheme == .dark ? DesignColors.darkSurface : DesignColors.lightSurface)
    }
}

/// 设计稿画布背景（随浅色/深色主题切换）
struct CanvasBackgroundView: View {
    @Environment(\.colorScheme) var colorScheme
    var body: some View {
        (colorScheme == .dark ? DesignColors.darkCanvasBg : DesignColors.lightCanvasBg)
    }
}

/// 设计稿画布网格：40px 格子，1px 线，设计稿指定透明度
struct CanvasGridView: View {
    @Environment(\.colorScheme) var colorScheme
    private let gridSize: CGFloat = DesignSizes.canvasGridSize
    private let lineWidth: CGFloat = DesignSizes.canvasGridLineWidth

    var body: some View {
        GeometryReader { geo in
            let cols = Int(geo.size.width / gridSize) + 2
            let rows = Int(geo.size.height / gridSize) + 2
            let gridColor = colorScheme == .dark ? DesignColors.darkCanvasGrid : DesignColors.lightCanvasGrid
            let opacity = colorScheme == .dark ? 0.35 : 0.5
            Canvas { context, size in
                for i in 0..<cols {
                    let x = CGFloat(i) * gridSize
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    context.stroke(path, with: .color(gridColor.opacity(opacity)), lineWidth: lineWidth)
                }
                for i in 0..<rows {
                    let y = CGFloat(i) * gridSize
                    var path = Path()
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    context.stroke(path, with: .color(gridColor.opacity(opacity)), lineWidth: lineWidth)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// 根据当前外观返回设计稿颜色
struct DesignTheme {
    @Environment(\.colorScheme) var colorScheme

    var canvasBg: Color {
        colorScheme == .dark ? DesignColors.darkCanvasBg : DesignColors.lightCanvasBg
    }
    var canvasGridColor: Color {
        colorScheme == .dark ? DesignColors.darkCanvasGrid : DesignColors.lightCanvasGrid
    }
    var canvasGridOpacity: Double {
        colorScheme == .dark ? 0.35 : 0.5
    }
    var surface2: Color {
        colorScheme == .dark ? DesignColors.darkSurface2 : DesignColors.lightSurface2
    }
    var surface3: Color {
        colorScheme == .dark ? DesignColors.darkSurface3 : DesignColors.lightSurface3
    }
    var border: Color {
        colorScheme == .dark ? DesignColors.darkBorder : DesignColors.lightBorder
    }
    var text: Color {
        colorScheme == .dark ? DesignColors.darkText : DesignColors.lightText
    }
    var text2: Color {
        colorScheme == .dark ? DesignColors.darkText2 : DesignColors.lightText2
    }
    var text3: Color {
        colorScheme == .dark ? DesignColors.darkText3 : DesignColors.lightText3
    }
    var accent: Color {
        colorScheme == .dark ? DesignColors.darkAccent : DesignColors.lightAccent
    }
}

// MARK: - 画布节点颜色（UserDefaults ↔ Color ↔ Metal）

enum DisplayCanvasNodeColor {
    static let junctionKey = "settings.display.nodeRGB.junction"
    static let reservoirKey = "settings.display.nodeRGB.reservoir"
    static let tankKey = "settings.display.nodeRGB.tank"
    /// 与旧版 Metal 默认 / 设置页示意接近（sRGB 8bit）
    static let defaultJunction = 0x1A3380
    static let defaultReservoir = 0x7D3EB8
    static let defaultTank = 0x34A853

    static func rgbFloats(packed: Int) -> (Float, Float, Float) {
        let r = Float((packed >> 16) & 0xFF) / 255
        let g = Float((packed >> 8) & 0xFF) / 255
        let b = Float(packed & 0xFF) / 255
        return (r, g, b)
    }
}

// MARK: - 画布管段颜色（UserDefaults ↔ Color ↔ Metal）

enum DisplayCanvasLinkColor {
    static let pipeKey = "settings.display.linkRGB.pipe"
    static let valveKey = "settings.display.linkRGB.valve"
    static let pumpKey = "settings.display.linkRGB.pump"
    /// 与旧版管线默认 / 设置页示意接近（sRGB 8bit）
    static let defaultPipe = 0x3366B2
    static let defaultValve = 0x3366B2
    static let defaultPump = 0xCC3333

    static func rgbFloats(packed: Int) -> (Float, Float, Float) {
        DisplayCanvasNodeColor.rgbFloats(packed: packed)
    }
}

extension Color {
    /// `packed` = 0xRRGGBB（不含 alpha）
    init(srgbRGB24 packed: Int) {
        let r = Double((packed >> 16) & 0xFF) / 255
        let g = Double((packed >> 8) & 0xFF) / 255
        let b = Double(packed & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }

    /// 转为 sRGB 0xRRGGBB，失败时返回 `fallback`
    func toSRGBRGB24(fallback: Int = DisplayCanvasNodeColor.defaultJunction) -> Int {
        #if os(macOS)
        guard let n = NSColor(self).usingColorSpace(.sRGB) else { return fallback }
        let r = Int(round(n.redComponent * 255))
        let g = Int(round(n.greenComponent * 255))
        let b = Int(round(n.blueComponent * 255))
        return (r << 16) | (g << 8) | b
        #else
        guard let n = UIColor(self).cgColor.converted(
            to: CGColorSpace(name: CGColorSpace.sRGB)!,
            intent: .defaultIntent,
            options: nil
        ), let comps = n.components, comps.count >= 3 else { return fallback }
        let r = Int(round(comps[0] * 255))
        let g = Int(round(comps[1] * 255))
        let b = Int(round(comps[2] * 255))
        return (r << 16) | (g << 8) | b
        #endif
    }
}
