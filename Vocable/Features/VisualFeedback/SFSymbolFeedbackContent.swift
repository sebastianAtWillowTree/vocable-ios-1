//
//  SFSymbolFeedbackContent.swift
//  Vocable
//
//  Copyright © 2025 WillowTree. All rights reserved.
//

import UIKit

/// Animated SF Symbol feedback (requires iOS 17+ for symbol effects).
@available(iOS 17.0, *)
struct SFSymbolFeedbackContent: VisualFeedbackContent {

    enum SymbolAnimationKind: Sendable {
        case bounce
        case pulse
    }

    let symbolName: String
    let animationKind: SymbolAnimationKind
    let tintColor: UIColor
    let displayDuration: TimeInterval
    let backgroundColor: UIColor

    init(
        symbolName: String,
        animationKind: SymbolAnimationKind,
        tintColor: UIColor,
        displayDuration: TimeInterval = 1.0,
        backgroundColor: UIColor = UIColor.black.withAlphaComponent(0.92)
    ) {
        self.symbolName = symbolName
        self.animationKind = animationKind
        self.tintColor = tintColor
        self.displayDuration = displayDuration
        self.backgroundColor = backgroundColor
    }

    func makeContentView() -> UIView {
        let config = UIImage.SymbolConfiguration(pointSize: 200, weight: .regular)
        let image = UIImage(systemName: symbolName, withConfiguration: config)
            ?? UIImage(systemName: "questionmark.circle.fill", withConfiguration: config)
        let imageView = UIImageView(image: image)
        imageView.tintColor = tintColor
        imageView.contentMode = .scaleAspectFit
        imageView.preferredSymbolConfiguration = config

        switch animationKind {
        case .bounce:
            imageView.addSymbolEffect(.bounce)
        case .pulse:
            imageView.addSymbolEffect(.pulse)
        }

        return imageView
    }
}
