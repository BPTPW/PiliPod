import SwiftUI

#if canImport(UIKit)
import UIKit

/// Presents the listen-video detail full screen so one SwiftUI background can
/// cover the status-bar area while UIKit supplies an interactive dismissal.
struct NativeListenVideoSheetPresenter<SheetContent: View>: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> SheetContent

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIViewController(context: Context) -> PresenterViewController {
        PresenterViewController()
    }

    func updateUIViewController(_ presenter: PresenterViewController, context: Context) {
        let rootView = AnyView(content().ignoresSafeArea())

        if isPresented {
            presenter.presentIfNeeded(rootView: rootView, coordinator: context.coordinator)
        } else {
            presenter.dismissIfNeeded()
        }
    }

    final class Coordinator: NSObject, UIViewControllerTransitioningDelegate, UIAdaptivePresentationControllerDelegate, UIGestureRecognizerDelegate {
        private var isPresented: Binding<Bool>
        private var dismissalInteraction: UIPercentDrivenInteractiveTransition?
        private weak var presentedController: UIViewController?

        init(isPresented: Binding<Bool>) {
            self.isPresented = isPresented
        }

        func presentationControllerDidDismiss(_: UIPresentationController) {
            isPresented.wrappedValue = false
        }

        func presentationController(
            forPresented presented: UIViewController,
            presenting: UIViewController?,
            source: UIViewController
        ) -> UIPresentationController? {
            let controller = ListenVideoPresentationController(
                presentedViewController: presented,
                presenting: presenting ?? source
            )
            controller.delegate = self
            return controller
        }

        func animationController(
            forPresented _: UIViewController,
            presenting _: UIViewController,
            source _: UIViewController
        ) -> (any UIViewControllerAnimatedTransitioning)? {
            ListenVideoSlideAnimator(isPresenting: true)
        }

        func animationController(forDismissed _: UIViewController) -> (any UIViewControllerAnimatedTransitioning)? {
            ListenVideoSlideAnimator(isPresenting: false)
        }

        func interactionControllerForDismissal(
            using _: any UIViewControllerAnimatedTransitioning
        ) -> (any UIViewControllerInteractiveTransitioning)? {
            dismissalInteraction
        }

        func installDismissalPanGesture(on controller: UIViewController) {
            presentedController = controller
            let panGesture = UIPanGestureRecognizer(target: self, action: #selector(handleDismissalPan(_:)))
            panGesture.delegate = self
            controller.view.addGestureRecognizer(panGesture)
        }

        @objc private func handleDismissalPan(_ gesture: UIPanGestureRecognizer) {
            guard let view = gesture.view else { return }
            let translation = gesture.translation(in: view)
            let progress = min(max(translation.y / max(view.bounds.height, 1), 0), 1)

            switch gesture.state {
            case .began:
                dismissalInteraction = UIPercentDrivenInteractiveTransition()
                presentedController?.dismiss(animated: true)
            case .changed:
                dismissalInteraction?.update(progress)
            case .ended, .cancelled, .failed:
                let velocity = gesture.velocity(in: view).y
                if progress > 0.24 || velocity > 1_000 {
                    dismissalInteraction?.finish()
                } else {
                    dismissalInteraction?.cancel()
                }
                dismissalInteraction = nil
            default:
                break
            }
        }

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let panGesture = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = panGesture.view
            else { return false }

            let velocity = panGesture.velocity(in: view)
            return velocity.y > 0 && velocity.y > abs(velocity.x)
        }
    }

    final class PresenterViewController: UIViewController {
        private var sheetController: ListenVideoHostingController?

        func presentIfNeeded(rootView: AnyView, coordinator: Coordinator) {
            if let sheetController {
                if sheetController.presentingViewController === self {
                    sheetController.rootView = rootView
                    return
                }
                self.sheetController = nil
            }

            guard viewIfLoaded?.window != nil else {
                DispatchQueue.main.async { [weak self] in
                    self?.presentIfNeeded(rootView: rootView, coordinator: coordinator)
                }
                return
            }

            let controller = ListenVideoHostingController(rootView: rootView)
            controller.modalPresentationStyle = .custom
            controller.modalPresentationCapturesStatusBarAppearance = true
            controller.transitioningDelegate = coordinator
            coordinator.installDismissalPanGesture(on: controller)

            present(controller, animated: true)
            sheetController = controller
        }

        func dismissIfNeeded() {
            guard let sheetController else { return }
            dismiss(animated: true) { [weak self] in
                self?.sheetController = nil
            }
        }
    }
}

private final class ListenVideoHostingController: UIHostingController<AnyView> {
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .clear
        view.isOpaque = false
    }

    override var preferredStatusBarStyle: UIStatusBarStyle { .lightContent }

    override var prefersStatusBarHidden: Bool { false }
}

private final class ListenVideoPresentationController: UIPresentationController {
    override var frameOfPresentedViewInContainerView: CGRect {
        containerView?.bounds ?? .zero
    }

    override func presentationTransitionWillBegin() {
        presentedView?.frame = frameOfPresentedViewInContainerView
    }

    override func containerViewWillLayoutSubviews() {
        presentedView?.frame = frameOfPresentedViewInContainerView
    }
}

private final class ListenVideoSlideAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    private let isPresenting: Bool

    init(isPresenting: Bool) {
        self.isPresenting = isPresenting
    }

    func transitionDuration(using _: (any UIViewControllerContextTransitioning)?) -> TimeInterval {
        0.38
    }

    func animateTransition(using context: any UIViewControllerContextTransitioning) {
        let container = context.containerView
        let duration = transitionDuration(using: context)

        if isPresenting {
            guard let toView = context.view(forKey: .to) else {
                context.completeTransition(false)
                return
            }
            toView.frame = context.finalFrame(for: context.viewController(forKey: .to)!)
            toView.transform = CGAffineTransform(translationX: 0, y: container.bounds.height)
            container.addSubview(toView)

            UIView.animate(
                withDuration: duration,
                delay: 0,
                usingSpringWithDamping: 0.9,
                initialSpringVelocity: 0.2,
                options: [.curveEaseOut]
            ) {
                toView.transform = .identity
            } completion: { _ in
                context.completeTransition(!context.transitionWasCancelled)
            }
        } else {
            guard let fromView = context.view(forKey: .from) else {
                context.completeTransition(false)
                return
            }
            UIView.animate(withDuration: duration, delay: 0, options: [.curveEaseOut]) {
                fromView.transform = CGAffineTransform(translationX: 0, y: container.bounds.height)
            } completion: { _ in
                fromView.transform = .identity
                context.completeTransition(!context.transitionWasCancelled)
            }
        }
    }
}
#else
struct NativeListenVideoSheetPresenter<SheetContent: View>: View {
    @Binding var isPresented: Bool
    @ViewBuilder let content: () -> SheetContent

    var body: some View {
        EmptyView()
    }
}
#endif
