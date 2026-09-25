import UIKit

final class FireMainCardAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    enum Operation {
        case push
        case pop
    }

    private let duration: TimeInterval = 0.28
    private let operation: Operation
    private let parallaxDistanceRatio: CGFloat
    var navigationBarSnapshot: UIView?
    weak var navigationBarSnapshotHost: UIView?

    init(operation: Operation, parallaxDistanceRatio: CGFloat) {
        self.operation = operation
        self.parallaxDistanceRatio = parallaxDistanceRatio
    }

    func transitionDuration(using transitionContext: UIViewControllerContextTransitioning?) -> TimeInterval {
        duration
    }

    func animateTransition(using transitionContext: UIViewControllerContextTransitioning) {
        guard let fromView = transitionContext.view(forKey: .from),
              let toView = transitionContext.view(forKey: .to) else {
            transitionContext.completeTransition(!transitionContext.transitionWasCancelled)
            return
        }

        let containerView = transitionContext.containerView
        let width = max(containerView.bounds.width, 1)
        let toViewController = transitionContext.viewController(forKey: .to)
        if let toViewController {
            toView.frame = transitionContext.finalFrame(for: toViewController)
        } else {
            toView.frame = containerView.bounds
        }

        switch operation {
        case .push:
            // Incoming secondary page slides from the right over the still tab shell.
            toView.transform = CGAffineTransform(translationX: width, y: 0)
            containerView.addSubview(toView)
            applyOutgoingShadow(to: toView)

            UIView.animate(
                withDuration: transitionDuration(using: transitionContext),
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    toView.transform = .identity
                    fromView.transform = CGAffineTransform(translationX: -width * self.parallaxDistanceRatio, y: 0)
                },
                completion: { _ in
                    let cancelled = transitionContext.transitionWasCancelled
                    fromView.transform = .identity
                    toView.transform = .identity
                    self.clearOutgoingShadow(from: toView)
                    if cancelled {
                        toView.removeFromSuperview()
                    }
                    transitionContext.completeTransition(!cancelled)
                }
            )

        case .pop:
            // Outgoing page slides right. Optional nav-bar snapshot rides with it so the real
            // bar (already swapped to the destination) stays covered — WeChat whole-page card.
            toView.transform = CGAffineTransform(translationX: -width * parallaxDistanceRatio, y: 0)
            containerView.insertSubview(toView, belowSubview: fromView)
            applyOutgoingShadow(to: fromView)

            let barSnapshot = navigationBarSnapshot
            let barHost = navigationBarSnapshotHost
            navigationBarSnapshot = nil
            navigationBarSnapshotHost = nil
            if let barSnapshot, let barHost {
                let barFrame: CGRect
                if let navigationBar = transitionContext.viewController(forKey: .from)?.navigationController?.navigationBar {
                    barFrame = navigationBar.convert(navigationBar.bounds, to: barHost)
                } else {
                    barFrame = CGRect(
                        x: 0,
                        y: barHost.safeAreaInsets.top,
                        width: barHost.bounds.width,
                        height: max(barSnapshot.bounds.height, 44)
                    )
                }
                barSnapshot.frame = barFrame
                barHost.addSubview(barSnapshot)
            }

            UIView.animate(
                withDuration: transitionDuration(using: transitionContext),
                delay: 0,
                options: [.curveEaseOut, .allowUserInteraction],
                animations: {
                    fromView.transform = CGAffineTransform(translationX: width, y: 0)
                    barSnapshot?.transform = CGAffineTransform(translationX: width, y: 0)
                    toView.transform = .identity
                },
                completion: { _ in
                    let cancelled = transitionContext.transitionWasCancelled
                    fromView.transform = .identity
                    toView.transform = .identity
                    barSnapshot?.removeFromSuperview()
                    self.clearOutgoingShadow(from: fromView)
                    if cancelled {
                        toView.removeFromSuperview()
                    }
                    transitionContext.completeTransition(!cancelled)
                }
            )
        }
    }

    private func applyOutgoingShadow(to view: UIView) {
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.18
        view.layer.shadowRadius = 12
        view.layer.shadowOffset = CGSize(width: -3, height: 0)
    }

    private func clearOutgoingShadow(from view: UIView) {
        view.layer.shadowOpacity = 0
        view.layer.shadowRadius = 0
        view.layer.shadowOffset = .zero
        view.layer.shadowColor = nil
    }
}
