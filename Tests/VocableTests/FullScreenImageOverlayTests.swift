//
//  FullScreenImageOverlayTests.swift
//  VocableTests
//
//  Drives the overlay's show / replace / dismiss bookkeeping with an
//  injected (synchronous) dismiss scheduler so the auto-dismiss is
//  deterministic.
//

import XCTest
import UIKit
@testable import Vocable

final class FullScreenImageOverlayTests: XCTestCase {

    private var window: UIWindow!
    private var overlay: FullScreenImageOverlay!
    private var capturedDismiss: (() -> Void)?

    override func setUp() {
        super.setUp()
        window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        overlay = FullScreenImageOverlay()
        // Capture the scheduled dismissal instead of firing it on a timer.
        overlay.scheduleDismiss = { [weak self] _, work in
            self?.capturedDismiss = work
            return DispatchWorkItem(block: work)
        }
    }

    override func tearDown() {
        capturedDismiss = nil
        overlay = nil
        window = nil
        super.tearDown()
    }

    func test_show_addsBackdrop_andMarksPresenting() {
        XCTAssertFalse(overlay.isPresenting)
        overlay.show(image: makeImage(), in: window, duration: 3)
        XCTAssertTrue(overlay.isPresenting)
        XCTAssertEqual(window.subviews.count, 1, "Exactly one backdrop should be added")
    }

    func test_show_twice_replaces_doesNotStack() {
        overlay.show(image: makeImage(), in: window, duration: 3)
        overlay.show(image: makeImage(), in: window, duration: 3)
        XCTAssertEqual(window.subviews.count, 1, "Second show should replace, not stack")
        XCTAssertTrue(overlay.isPresenting)
    }

    func test_scheduledDismiss_clearsPresentingState() {
        overlay.show(image: makeImage(), in: window, duration: 3)
        XCTAssertTrue(overlay.isPresenting)
        // Fire the captured auto-dismiss work.
        capturedDismiss?()
        XCTAssertFalse(overlay.isPresenting, "Auto-dismiss should clear the presenting state")
    }

    func test_explicitDismiss_whenNothingShown_isNoOp() {
        XCTAssertNoThrow(overlay.dismiss())
        XCTAssertFalse(overlay.isPresenting)
    }

    func test_dismiss_clearsPresentingState() {
        overlay.show(image: makeImage(), in: window, duration: 3)
        overlay.dismiss()
        XCTAssertFalse(overlay.isPresenting)
    }

    // MARK: - Helpers

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 10, height: 10), format: format).image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
        }
    }
}
