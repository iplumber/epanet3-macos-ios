#if os(macOS)
import AppKit
import SwiftUI

/// 对象表单元格：独立 NSWindow + 嵌套 ScrollView 下 SwiftUI `TextField` 往往无法成为第一响应者，改用 AppKit 文本框。
struct ObjectTableEditableCellMac: NSViewRepresentable {
    @Binding var text: String
    var font: NSFont
    var textAlignment: NSTextAlignment
    var onBeginEditing: () -> Void
    /// 结束时传入控件内最终字符串（与 `text` 同步）。
    var onEndEditing: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSTextField {
        let tf = NSTextField(string: text)
        tf.isBordered = false
        tf.isBezeled = false
        tf.drawsBackground = false
        tf.backgroundColor = .clear
        tf.focusRingType = .none
        tf.font = font
        tf.alignment = textAlignment
        tf.lineBreakMode = .byTruncatingTail
        tf.cell?.sendsActionOnEndEditing = true
        tf.delegate = context.coordinator
        context.coordinator.textField = tf
        context.coordinator.textBinding = $text
        context.coordinator.onBeginEditing = onBeginEditing
        context.coordinator.onEndEditing = onEndEditing
        return tf
    }

    func updateNSView(_ nsView: NSTextField, context: Context) {
        context.coordinator.textBinding = $text
        context.coordinator.onBeginEditing = onBeginEditing
        context.coordinator.onEndEditing = onEndEditing
        nsView.font = font
        nsView.alignment = textAlignment
        let isFirstResponder = (nsView.window?.firstResponder as AnyObject?) === nsView
        if !isFirstResponder, nsView.stringValue != text {
            nsView.stringValue = text
        }
    }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        weak var textField: NSTextField?
        var textBinding: Binding<String>?
        var onBeginEditing: (() -> Void)?
        var onEndEditing: ((String) -> Void)?

        func controlTextDidBeginEditing(_ notification: Notification) {
            onBeginEditing?()
        }

        func controlTextDidChange(_ obj: Notification) {
            guard let tf = textField, let b = textBinding else { return }
            b.wrappedValue = tf.stringValue
        }

        func controlTextDidEndEditing(_ obj: Notification) {
            guard let tf = textField else { return }
            onEndEditing?(tf.stringValue)
        }
    }
}
#endif
