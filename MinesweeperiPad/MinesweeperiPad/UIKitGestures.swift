import SwiftUI
import UIKit

struct CellGestureOverlay: UIViewRepresentable {
    var onTap: () -> Void              // 单击：挖开
    var onDoubleTap: () -> Void        // 双击：chord
    var onTwoFingerTap: () -> Void     // 双指点击：chord
    var onLongPressOneFinger: () -> Void  // 长按：标记雷

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isOpaque = false
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1
        tap.require(toFail: doubleTap)

        let twoFingerTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTwoFingerTap))
        twoFingerTap.numberOfTapsRequired = 1
        twoFingerTap.numberOfTouchesRequired = 2

        let longPress = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35
        longPress.numberOfTouchesRequired = 1

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(twoFingerTap)
        view.addGestureRecognizer(longPress)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onTwoFingerTap = onTwoFingerTap
        context.coordinator.onLongPressOneFinger = onLongPressOneFinger
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onTwoFingerTap: onTwoFingerTap,
            onLongPressOneFinger: onLongPressOneFinger
        )
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onDoubleTap: () -> Void
        var onTwoFingerTap: () -> Void
        var onLongPressOneFinger: () -> Void

        init(
            onTap: @escaping () -> Void,
            onDoubleTap: @escaping () -> Void,
            onTwoFingerTap: @escaping () -> Void,
            onLongPressOneFinger: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onDoubleTap = onDoubleTap
            self.onTwoFingerTap = onTwoFingerTap
            self.onLongPressOneFinger = onLongPressOneFinger
        }

        @objc func handleTap() {
            onTap()
        }

        @objc func handleDoubleTap() {
            onDoubleTap()
        }

        @objc func handleTwoFingerTap() {
            onTwoFingerTap()
        }

        @objc func handleLongPress(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            onLongPressOneFinger()
        }
    }
}
