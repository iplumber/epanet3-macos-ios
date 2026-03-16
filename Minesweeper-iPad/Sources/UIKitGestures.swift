import SwiftUI
import UIKit

struct CellGestureOverlay: UIViewRepresentable {
    var onTap: () -> Void
    var onDoubleTap: () -> Void
    var onLongPressOneFinger: () -> Void
    var onLongPressTwoFingers: () -> Void

    func makeUIView(context: Context) -> UIView {
        let view = PassthroughView()
        view.isOpaque = false
        view.backgroundColor = .clear

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap))
        tap.numberOfTapsRequired = 1
        tap.numberOfTouchesRequired = 1

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        doubleTap.numberOfTouchesRequired = 1

        tap.require(toFail: doubleTap)

        let longPress1 = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress1(_:)))
        longPress1.minimumPressDuration = 0.32
        longPress1.numberOfTouchesRequired = 1

        let longPress2 = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress2(_:)))
        longPress2.minimumPressDuration = 0.32
        longPress2.numberOfTouchesRequired = 2

        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(longPress1)
        view.addGestureRecognizer(longPress2)

        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.onDoubleTap = onDoubleTap
        context.coordinator.onLongPressOneFinger = onLongPressOneFinger
        context.coordinator.onLongPressTwoFingers = onLongPressTwoFingers
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            onTap: onTap,
            onDoubleTap: onDoubleTap,
            onLongPressOneFinger: onLongPressOneFinger,
            onLongPressTwoFingers: onLongPressTwoFingers
        )
    }

    final class Coordinator: NSObject {
        var onTap: () -> Void
        var onDoubleTap: () -> Void
        var onLongPressOneFinger: () -> Void
        var onLongPressTwoFingers: () -> Void

        init(
            onTap: @escaping () -> Void,
            onDoubleTap: @escaping () -> Void,
            onLongPressOneFinger: @escaping () -> Void,
            onLongPressTwoFingers: @escaping () -> Void
        ) {
            self.onTap = onTap
            self.onDoubleTap = onDoubleTap
            self.onLongPressOneFinger = onLongPressOneFinger
            self.onLongPressTwoFingers = onLongPressTwoFingers
        }

        @objc func handleTap() {
            onTap()
        }

        @objc func handleDoubleTap() {
            onDoubleTap()
        }

        @objc func handleLongPress1(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            onLongPressOneFinger()
        }

        @objc func handleLongPress2(_ gr: UILongPressGestureRecognizer) {
            guard gr.state == .began else { return }
            onLongPressTwoFingers()
        }
    }

    private final class PassthroughView: UIView {
        override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
            true
        }
    }
}

