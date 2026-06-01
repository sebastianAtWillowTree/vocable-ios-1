//
//  FullScreenImageOverlay.swift
//  Vocable
//
//  Briefly flashes a phrase's photo full-screen when the phrase is
//  selected — an AAC reinforcement cue so the picture the caregiver
//  attached is shown large alongside the spoken utterance.
//
//  Presentation notes:
//  - Added as a window-level subview so it covers the output bar and
//    nav, then auto-dismisses after `duration` (default 3s).
//  - Passive: it does not capture gaze targets. Head-tracking users
//    rely on the auto-dismiss; touch users can tap to dismiss early.
//  - Rapid re-selection replaces the current overlay rather than
//    stacking, and reschedules the dismissal.
//  - The dimmed backdrop lets subject-lifted (transparent) cartoons
//    read clearly.
//

import UIKit

final class FullScreenImageOverlay {

    static let shared = FullScreenImageOverlay()

    /// Schedules `work` after `delay`, returning a cancellable handle.
    /// Injectable so tests can drive the dismissal synchronously.
    var scheduleDismiss: (TimeInterval, @escaping () -> Void) -> DispatchWorkItem = { delay, work in
        let item = DispatchWorkItem(block: work)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
        return item
    }

    private var currentBackdrop: UIView?
    private var pendingDismiss: DispatchWorkItem?

    /// True while an overlay is on screen. Exposed for tests.
    var isPresenting: Bool { currentBackdrop != nil }

    init() {}

    /// Presents `image` full-screen over `window` for `duration`,
    /// replacing any overlay already on screen.
    func show(image: UIImage, in window: UIWindow, duration: TimeInterval = 1.75) {
        pendingDismiss?.cancel()
        currentBackdrop?.removeFromSuperview()

        let backdrop = makeBackdrop(image: image, frame: window.bounds)
        window.addSubview(backdrop)
        currentBackdrop = backdrop

        backdrop.alpha = 0
        UIView.animate(withDuration: 0.15) { backdrop.alpha = 1 }

        pendingDismiss = scheduleDismiss(duration) { [weak self] in
            self?.dismiss()
        }
    }

    /// Dismisses the current overlay (if any) and cancels the pending
    /// auto-dismiss. Safe to call repeatedly.
    func dismiss() {
        pendingDismiss?.cancel()
        pendingDismiss = nil
        guard let backdrop = currentBackdrop else { return }
        currentBackdrop = nil
        UIView.animate(
            withDuration: 0.2,
            animations: { backdrop.alpha = 0 },
            completion: { _ in backdrop.removeFromSuperview() }
        )
    }

    // MARK: - Private

    @objc private func handleTap() {
        dismiss()
    }

    private func makeBackdrop(image: UIImage, frame: CGRect) -> UIView {
        let backdrop = UIView(frame: frame)
        backdrop.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        backdrop.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        // Decorative; do not trap assistive focus on a transient flash.
        backdrop.isAccessibilityElement = false

        let imageView = UIImageView(image: image)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.contentMode = .scaleAspectFit
        imageView.isAccessibilityElement = false
        backdrop.addSubview(imageView)

        NSLayoutConstraint.activate([
            imageView.centerXAnchor.constraint(equalTo: backdrop.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: backdrop.centerYAnchor),
            imageView.widthAnchor.constraint(lessThanOrEqualTo: backdrop.widthAnchor, multiplier: 0.9),
            imageView.heightAnchor.constraint(lessThanOrEqualTo: backdrop.heightAnchor, multiplier: 0.9)
        ])

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        backdrop.addGestureRecognizer(tap)
        return backdrop
    }
}
