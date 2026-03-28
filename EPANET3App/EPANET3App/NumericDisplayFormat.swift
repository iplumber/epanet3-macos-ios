import Foundation

/// 界面数值展示：管长/管径、管段流量/流速等（与 .inp 写盘格式无关）。
enum NumericDisplayFormat {
    private static let posixLocale = Locale(identifier: "en_US_POSIX")

    /// 管长、管径：值为整数时不显示小数；有小数时最多两位，并按常规舍入。
    static func formatPipeLengthOrDiameter(_ value: Double) -> String {
        let nf = NumberFormatter()
        nf.locale = Self.posixLocale
        nf.numberStyle = .decimal
        nf.minimumFractionDigits = 0
        nf.maximumFractionDigits = 2
        nf.roundingMode = .halfEven
        return nf.string(from: NSNumber(value: value)) ?? String(value)
    }

    /// 管段流量、流速：固定两位小数。
    static func formatLinkFlowOrVelocity(_ value: Double) -> String {
        String(format: "%.2f", value)
    }
}
