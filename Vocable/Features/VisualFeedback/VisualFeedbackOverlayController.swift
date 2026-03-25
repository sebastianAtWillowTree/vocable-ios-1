//
//  VisualFeedbackOverlayController.swift
//  Vocable
//
//  Copyright © 2025 WillowTree. All rights reserved.
//

import UIKit

/// Presents full-screen phrase activation feedback above the main interface (below the gaze cursor window).
final class VisualFeedbackOverlayController {

    static let shared = VisualFeedbackOverlayController()

    private weak var overlayView: VisualFeedbackOverlayView?
    private var dismissWorkItem: DispatchWorkItem?

    private init() {}

    func present(content: AnyVisualFeedbackContent, utterance: String, in window: UIWindow) {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil

        overlayView?.removeFromSuperview()

        let view = VisualFeedbackOverlayView(content: content, utterance: utterance)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.alpha = 0
        view.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)

        window.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: window.topAnchor),
            view.leadingAnchor.constraint(equalTo: window.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: window.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: window.bottomAnchor)
        ])

        overlayView = view

        UIView.animate(
            withDuration: 0.15,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseOut],
            animations: {
                view.alpha = 1
                view.transform = .identity
            },
            completion: nil
        )

        let hold = content.displayDuration
        let work = DispatchWorkItem { [weak self] in
            self?.dismissAnimated()
        }
        dismissWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15 + hold, execute: work)
    }

    func dismiss() {
        dismissWorkItem?.cancel()
        dismissWorkItem = nil
        overlayView?.removeFromSuperview()
        overlayView = nil
    }

    private func dismissAnimated() {
        guard let view = overlayView else { return }
        UIView.animate(
            withDuration: 0.2,
            delay: 0,
            options: [.beginFromCurrentState, .curveEaseIn],
            animations: {
                view.alpha = 0
            },
            completion: { [weak self] _ in
                view.removeFromSuperview()
                if self?.overlayView === view {
                    self?.overlayView = nil
                }
            }
        )
    }
}
