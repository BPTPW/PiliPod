import SwiftUI

#if canImport(UIKit)
import UIKit

/// Re-enables UIKit's own edge-pop recognizer without replacing its delegate.
/// The delegate is responsible for rejecting an interactive pop during an
/// in-flight transition, so it must remain under UIKit's control.
struct NavigationPopGestureEnabler: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> Controller {
        Controller()
    }

    func updateUIViewController(_ uiViewController: Controller, context: Context) {
        uiViewController.enableSystemPopGestureIfPossible()
    }

    final class Controller: UIViewController {
        private weak var installedNavigationController: UINavigationController?
        private var originalDelegate: UIGestureRecognizerDelegate?
        private var delegateProxy: PopGestureDelegateProxy?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            enableSystemPopGestureIfPossible()
        }

        override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            enableSystemPopGestureIfPossible()
        }

        func enableSystemPopGestureIfPossible() {
            guard let navigationController = containingNavigationController(),
                  let gesture = navigationController.interactivePopGestureRecognizer
            else {
                DispatchQueue.main.async { [weak self] in
                    self?.installIfPossibleOnNextRunLoop()
                }
                return
            }

            if installedNavigationController !== navigationController {
                restorePreviousDelegate()
                installedNavigationController = navigationController
                originalDelegate = gesture.delegate
                let proxy = PopGestureDelegateProxy(
                    original: originalDelegate,
                    navigationController: navigationController
                )
                delegateProxy = proxy
                gesture.delegate = proxy
            }
            gesture.isEnabled = true
        }

        private func installIfPossibleOnNextRunLoop() {
            enableSystemPopGestureIfPossible()
        }

        private func containingNavigationController() -> UINavigationController? {
            var controller: UIViewController? = self
            while let current = controller {
                if let navigationController = current.navigationController {
                    return navigationController
                }
                controller = current.parent
            }
            return nil
        }

        private func restorePreviousDelegate() {
            guard let navigationController = installedNavigationController,
                  let gesture = navigationController.interactivePopGestureRecognizer,
                  gesture.delegate === delegateProxy
            else { return }
            gesture.delegate = originalDelegate
            delegateProxy = nil
            originalDelegate = nil
        }

        deinit {
            restorePreviousDelegate()
        }
    }
}

private final class PopGestureDelegateProxy: NSObject, UIGestureRecognizerDelegate {
    weak var original: UIGestureRecognizerDelegate?
    weak var navigationController: UINavigationController?

    init(original: UIGestureRecognizerDelegate?, navigationController: UINavigationController) {
        self.original = original
        self.navigationController = navigationController
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let navigationController,
              navigationController.viewControllers.count > 1,
              navigationController.transitionCoordinator == nil,
              !navigationController.isBeingDismissed
        else { return false }

        return original?.gestureRecognizerShouldBegin?(gestureRecognizer) ?? true
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        original?.gestureRecognizer?(
            gestureRecognizer,
            shouldRecognizeSimultaneouslyWith: otherGestureRecognizer
        ) ?? false
    }
}
#else
struct NavigationPopGestureEnabler: View {
    var body: some View { EmptyView() }
}
#endif
