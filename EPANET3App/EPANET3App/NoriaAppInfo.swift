import Foundation

enum NoriaAppInfo {
    /// Bundle marketing version for Noria export line; matches Xcode `MARKETING_VERSION` when set in the app Info.plist.
    static var marketingVersionString: String {
        if let s = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty { return t }
        }
        return "1.0"
    }
}
