import SwiftUI
import UIKit

/// A stationary hold, rather than a zero-distance drag that competes with pans.
struct VideoTripleLikePressGesture: UIGestureRecognizerRepresentable {
    let isEnabled: Bool
    let onStarted: () -> Void
    let onFinished: () -> Void

    func makeCoordinator(converter: CoordinateSpaceConverter) -> Coordinator {
        Coordinator(gesture: self)
    }

    func makeUIGestureRecognizer(context: Context) -> UILongPressGestureRecognizer {
        let recognizer = UILongPressGestureRecognizer()
        recognizer.minimumPressDuration = 0.5
        recognizer.allowableMovement = 10
        recognizer.numberOfTouchesRequired = 1
        recognizer.delegate = context.coordinator
        return recognizer
    }

    func updateUIGestureRecognizer(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        context.coordinator.gesture = self
        recognizer.isEnabled = isEnabled
    }

    func handleUIGestureRecognizerAction(_ recognizer: UILongPressGestureRecognizer, context: Context) {
        let coordinator = context.coordinator
        switch recognizer.state {
        case .began:
            coordinator.isHolding = true
            onStarted()
        case .changed:
            // UIKit's allowableMovement guards recognition. Also cancel movement
            // during charging, using window coordinates unaffected by animation.
            guard let start = coordinator.startLocation else { return }
            let location = recognizer.location(in: recognizer.view?.window)
            if hypot(location.x - start.x, location.y - start.y) > recognizer.allowableMovement {
                coordinator.finish()
                recognizer.isEnabled = false
                recognizer.isEnabled = isEnabled
            }
        case .ended, .cancelled, .failed:
            coordinator.finish()
        default:
            break
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var gesture: VideoTripleLikePressGesture
        var startLocation: CGPoint?
        var isHolding = false

        init(gesture: VideoTripleLikePressGesture) {
            self.gesture = gesture
        }

        func gestureRecognizer(_ recognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard gesture.isEnabled, let window = touch.window else { return false }
            let location = touch.location(in: window)
            // Reserve both physical edges for system navigation gestures.
            guard location.x > window.bounds.minX + 32,
                  location.x < window.bounds.maxX - 32 else { return false }
            startLocation = location
            return true
        }

        func finish() {
            guard isHolding else { return }
            isHolding = false
            gesture.onFinished()
        }
    }
}
