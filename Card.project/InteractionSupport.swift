import SwiftUI
import UIKit

// 入力欄やキーボードの操作を妨げず、余白やボタンのタップで入力を終了する。
struct KeyboardDismissal: UIViewRepresentable {
    func makeUIView(context: Context) -> HostView { HostView() }
    func updateUIView(_ uiView: HostView, context: Context) { }

    final class HostView: UIView, UIGestureRecognizerDelegate {
        private weak var installedWindow: UIWindow?
        private lazy var tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))

        override func didMoveToWindow() {
            super.didMoveToWindow()
            installedWindow?.removeGestureRecognizer(tap)
            installedWindow = window
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window?.addGestureRecognizer(tap)
        }

        @objc private func dismissKeyboard() { installedWindow?.endEditing(true) }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            var view = touch.view
            while let current = view {
                if current is UITextInput { return false }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }
    }
}
