//
//  VisualFeedbackContent.swift
//  Vocable
//
//  Copyright © 2025 WillowTree. All rights reserved.
//

import UIKit

/// Describes full-screen visual feedback shown briefly when a phrase is activated.
/// Conform with concrete implementations (e.g. SF Symbols, Lottie, Core Animation).
protocol VisualFeedbackContent {

    func makeContentView() -> UIView

    var displayDuration: TimeInterval { get }

    var backgroundColor: UIColor { get }
}

extension VisualFeedbackContent {

    var displayDuration: TimeInterval { 1.0 }

    var backgroundColor: UIColor {
        UIColor.black.withAlphaComponent(0.92)
    }
}

/// Type-erased wrapper for storage in registries and presentation APIs.
struct AnyVisualFeedbackContent: VisualFeedbackContent {

    private let _makeContentView: () -> UIView
    let displayDuration: TimeInterval
    let backgroundColor: UIColor

    init(_ content: some VisualFeedbackContent) {
        self._makeContentView = { content.makeContentView() }
        self.displayDuration = content.displayDuration
        self.backgroundColor = content.backgroundColor
    }

    func makeContentView() -> UIView {
        _makeContentView()
    }
}
