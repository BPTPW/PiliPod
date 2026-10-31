import SwiftUI
import UIKit

/// Directional tab paging that yields unrelated drags to scrolling and navigation.
struct VideoDetailTabPanGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let isIntro: Bool
    let leadingExclusionWidth: CGFloat
    let onChanged: (CGFloat) -> Void
    let onEnded: (CGFloat?) -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(gesture: self, converter: converter)
    }

    func makeUIGestureRecognizer(context: Context) -> UIPanGestureRecognizer {
        let recognizer = UIPanGestureRecognizer()
        recognizer.maximumNumberOfTouches = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UIPanGestureRecognizer, context: Context) {
        context.coordinator.gesture = self
        context.coordinator.converter = context.converter
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UIPanGestureRecognizer, context: Context) {
        let translation = context.converter.localTranslation?.x ?? recognizer.translation(in: recognizer.view).x
        switch recognizer.state {
        case .began, .changed:
            onChanged(translation)
        case .ended:
            onEnded(translation)
        case .cancelled, .failed:
            onEnded(nil)
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gesture: VideoDetailTabPanGesture
        var converter: CoordinateSpaceConverter

        init(gesture: VideoDetailTabPanGesture, converter: CoordinateSpaceConverter) {
            self.gesture = gesture
            self.converter = converter
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            // Use the touch itself: the converter's current location need not
            // have been updated when UIKit asks whether to receive a new touch.
            guard gesture.isEnabled, let window = touch.window else { return false }
            return touch.location(in: window).x > window.bounds.minX + gesture.leadingExclusionWidth
        }

        func gestureRecognizerShouldBegin(_ recognizer: UIGestureRecognizer) -> Bool {
            guard gesture.isEnabled, let pan = recognizer as? UIPanGestureRecognizer else { return false }
            let velocity = pan.velocity(in: pan.view)
            guard abs(velocity.x) > abs(velocity.y) else { return false }
            // In the intro, a rightward pan belongs to native back navigation.
            return gesture.isIntro ? velocity.x < 0 : velocity.x > 0
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            // Vertical scrolling remains responsive while UIKit decides direction.
            guard let scrollView = other.view as? UIScrollView else { return false }
            return other === scrollView.panGestureRecognizer
        }

        func gestureRecognizer(
            _ recognizer: UIGestureRecognizer,
            shouldBeRequiredToFailBy other: UIGestureRecognizer
        ) -> Bool {
            // Content-back waits for this directional pan to fail. On the intro
            // a rightward pan fails immediately; on comments it pages to intro.
            guard #available(iOS 26.0, *), let navigation = navigationController(for: recognizer.view) else {
                return false
            }
            return other === navigation.interactiveContentPopGestureRecognizer
        }

        private func navigationController(for view: UIView?) -> UINavigationController? {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UIViewController,
                   let navigation = controller.navigationController {
                    return navigation
                }
                responder = current.next
            }
            return nil
        }
    }
}
