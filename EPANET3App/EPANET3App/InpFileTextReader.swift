/* 读取 .inp 文本：先按 UTF-8，失败则尝试常见单字节编码，避免 NSCocoa 259（非法 UTF-8） */
import Foundation

enum InpFileTextReader {
    /// 读取路径对应文件为文本（用于 Swift 侧解析；与 C++ 打开方式无关）。
    static func contentsOfFile(path: String) throws -> String {
        let url = URL(fileURLWithPath: path)
        var data = try Data(contentsOf: url)
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            data = Data(data.dropFirst(3))
        }
        return decodeInpData(data)
    }

    /// 将已读入的 Data 解码为 String（多编码回退，最后使用 UTF-8 有损解码）。
    static func decodeInpData(_ data: Data) -> String {
        if data.isEmpty { return "" }
        var data = data
        if data.count >= 3, data[0] == 0xEF, data[1] == 0xBB, data[2] == 0xBF {
            data = Data(data.dropFirst(3))
        }
        let encodings: [String.Encoding] = [
            .utf8,
            .utf16LittleEndian,
            .utf16BigEndian,
            .isoLatin1,
            .windowsCP1252,
            .macOSRoman,
            .ascii,
        ]
        for enc in encodings {
            if let s = String(data: data, encoding: enc), looksLikeInp(s) {
                return s
            }
        }
        for enc in encodings {
            if let s = String(data: data, encoding: enc) {
                return s
            }
        }
        return String(decoding: data, as: UTF8.self)
    }

    /// 粗略判断是否为 EPANET .inp 文本，避免把 UTF-16 误当合法内容。
    private static func looksLikeInp(_ s: String) -> Bool {
        let u = s.uppercased()
        guard u.contains("[") else { return false }
        return u.contains("JUNCTION") || u.contains("PIPE") || u.contains("RESERVOIR")
            || u.contains("TANK") || u.contains("OPTION") || u.contains("TITLE")
            || u.contains("PUMP") || u.contains("VALVE")
    }
}
