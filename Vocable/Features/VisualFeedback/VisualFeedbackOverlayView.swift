//
//  VisualFeedbackOverlayView.swift
//  Vocable
//
//  Copyright © 2025 WillowTree. All rights reserved.
//

import UIKit

/// Full-screen high-contrast overlay: animated content area + large utterance text.
final class VisualFeedbackOverlayView: UIView {

    private let contentContainer = UIView()
    private let utteranceLabel = UILabel()

    init(content: AnyVisualFeedbackContent, utterance: String) {
        super.init(frame: .zero)
        accessibilityElementsHidden = true
        isUserInteractionEnabled = false
        backgroundColor = content.backgroundColor

        let symbolView = content.makeContentView()
        symbolView.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.translatesAutoresizingMaskIntoConstraints = false

        contentContainer.addSubview(symbolView)
        NSLayoutConstraint.activate([
            symbolView.centerXAnchor.constraint(equalTo: contentContainer.centerXAnchor),
            symbolView.centerYAnchor.constraint(equalTo: contentContainer.centerYAnchor),
            symbolView.leadingAnchor.constraint(greaterThanOrEqualTo: contentContainer.leadingAnchor),
            symbolView.trailingAnchor.constraint(lessThanOrEqualTo: contentContainer.trailingAnchor),
            symbolView.topAnchor.constraint(greaterThanOrEqualTo: contentContainer.topAnchor),
            symbolView.bottomAnchor.constraint(lessThanOrEqualTo: contentContainer.bottomAnchor)
        ])

        utteranceLabel.text = utterance
        utteranceLabel.textColor = .white
        utteranceLabel.font = .systemFont(ofSize: 48, weight: .bold)
        utteranceLabel.textAlignment = .center
        utteranceLabel.numberOfLines = 0
        utteranceLabel.adjustsFontForContentSizeCategory = true
        utteranceLabel.translatesAutoresizingMaskIntoConstraints = false

        addSubview(contentContainer)
        addSubview(utteranceLabel)

        let guide = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            contentContainer.topAnchor.constraint(equalTo: guide.topAnchor),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: centerYAnchor, constant: 40),

            utteranceLabel.topAnchor.constraint(equalTo: contentContainer.bottomAnchor, constant: 24),
            utteranceLabel.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            utteranceLabel.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            utteranceLabel.bottomAnchor.constraint(lessThanOrEqualTo: guide.bottomAnchor, constant: -24)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
