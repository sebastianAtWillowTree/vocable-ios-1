//
//  PresetItemCollectionViewCell.swift
//  Vocable AAC
//
//  Created by Patrick Gatewood on 1/28/20.
//  Copyright © 2020 WillowTree. All rights reserved.
//

import UIKit

class PresetItemCollectionViewCell: VocableCollectionViewCell, HighlightableContentCell {

    let textLabel = UILabel(frame: .zero)

    let thumbnailImageView: UIImageView = {
        let view = UIImageView(frame: .zero)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.contentMode = .scaleAspectFit
        view.isHidden = true
        view.isAccessibilityElement = false
        return view
    }()

    private var textTopToContentTopConstraint: NSLayoutConstraint!
    private var textTopToThumbnailBottomConstraint: NSLayoutConstraint!
    private var activeThumbnailToken: ThumbnailLoadToken?

    private var highlightRange: NSRange?

    override func updateContent() {
        super.updateContent()

        let textColor: UIColor = {
            if isSelected {
                return .selectedTextColor
            }
            if !isEnabled {
                return UIColor.defaultTextColor.disabled(blending: borderedView.backgroundColor)
            }
            return .defaultTextColor
        }()

        textLabel.textColor = textColor
        textLabel.backgroundColor = borderedView.fillColor
        textLabel.isOpaque = true
        textLabel.font = UIFont.systemFont(ofSize: 28, weight: .bold)

        if let highlightRange, let attributedString = textLabel.attributedText {
            let attr = NSMutableAttributedString(attributedString: attributedString)
            attr.addAttribute(.foregroundColor, value: UIColor.cellBorderHighlightColor, range: highlightRange)
            textLabel.attributedText = attr
        }
    }
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    override func layoutMarginsDidChange() {
        super.layoutMarginsDidChange()
        textLabel.preferredMaxLayoutWidth = layoutMarginsGuide.layoutFrame.width
    }
    
    private func commonInit() {
        contentView.preservesSuperviewLayoutMargins = true

        textLabel.textAlignment = .center
        textLabel.numberOfLines = 0
        textLabel.adjustsFontSizeToFitWidth = true
        textLabel.minimumScaleFactor = 0.5

        textLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(thumbnailImageView)
        contentView.addSubview(textLabel)

        let layoutGuide = contentView.layoutMarginsGuide

        textTopToContentTopConstraint = textLabel.topAnchor.constraint(equalTo: layoutGuide.topAnchor)
        textTopToThumbnailBottomConstraint = textLabel.topAnchor.constraint(
            equalTo: thumbnailImageView.bottomAnchor, constant: 4
        )
        textTopToContentTopConstraint.isActive = true

        NSLayoutConstraint.activate([
            textLabel.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor).withPriority(999),
            textLabel.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor),
            textLabel.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor).withPriority(999),

            thumbnailImageView.topAnchor.constraint(equalTo: layoutGuide.topAnchor),
            thumbnailImageView.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor),
            thumbnailImageView.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor),
            thumbnailImageView.heightAnchor.constraint(
                equalTo: layoutGuide.heightAnchor, multiplier: 0.55
            ).withPriority(999)
        ])
    }

    /// Configures (or clears) the thumbnail shown above the text label.
    /// The cell's outer frame height is unaffected — the text region
    /// shrinks vertically when a thumbnail is present.
    func configureThumbnail(assetID: String?, loader: ThumbnailLoading) {
        activeThumbnailToken?.cancel()
        activeThumbnailToken = nil
        thumbnailImageView.image = nil

        guard let assetID, !assetID.isEmpty else {
            thumbnailImageView.isHidden = true
            textTopToThumbnailBottomConstraint.isActive = false
            textTopToContentTopConstraint.isActive = true
            return
        }

        thumbnailImageView.isHidden = false
        textTopToContentTopConstraint.isActive = false
        textTopToThumbnailBottomConstraint.isActive = true

        activeThumbnailToken = loader.loadThumbnail(
            id: assetID,
            targetSize: CGSize(width: 192, height: 192)
        ) { [weak self] image in
            self?.thumbnailImageView.image = image
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        activeThumbnailToken?.cancel()
        activeThumbnailToken = nil
        thumbnailImageView.image = nil
        thumbnailImageView.isHidden = true
        textTopToThumbnailBottomConstraint.isActive = false
        textTopToContentTopConstraint.isActive = true
    }

    func setup(title: String, with image: UIImage? = nil) {
        if let image = image {
            textLabel.attributedText = NSAttributedString.imageAttachedString(for: title, with: image)
        } else {
            textLabel.text = title
        }
    }

    @MainActor
    func setHighlightRange(_ range: NSRange?) {
        highlightRange = range
        UIView.transition(
            with: contentView,
            duration: 0.1,
            options: .transitionCrossDissolve
        ) { [weak self] in
            self?.setNeedsUpdateContent()
            self?.updateContent()
        }
    }
}

class CategoryItemCollectionViewCell: PresetItemCollectionViewCell {
    
    var roundedCorners: UIRectCorner {
        get {
            borderedView.roundedCorners
        }
        set {
            borderedView.roundedCorners = newValue
        }
    }
    
    override func updateContent() {
        super.updateContent()

        borderedView.fillColor = {
            var result: UIColor
            if isSelected {
                result = .cellSelectionColor
            } else {
                result = .categoryBackgroundColor
            }
            if isHighlighted && isTrackingTouches {
                result = result.darkenedForHighlight()
            }
            return result
        }()
        borderedView.backgroundColor = sizeClass.contains(any: .compact)
            ? .collectionViewBackgroundColor : .categoryBackgroundColor
        
        textLabel.textColor = isSelected ? .selectedTextColor : .defaultTextColor
        textLabel.backgroundColor = borderedView.fillColor
        textLabel.isOpaque = true
        textLabel.font = .systemFont(ofSize: 22, weight: .bold)
    }
}
