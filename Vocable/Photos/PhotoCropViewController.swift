//
//  PhotoCropViewController.swift
//  Vocable
//
//  Lightweight square-crop confirmation screen. The image is laid
//  out at aspectFit with a centered square overlay that indicates
//  what will be kept. The user can confirm (crop + save) or cancel.
//
//  Pan/zoom for repositioning the crop is intentionally deferred —
//  this MVP commits to the centered-square crop produced by
//  SquareCropper. A future ticket can add gesture handling here.
//

import UIKit

final class PhotoCropViewController: UIViewController {

    private let sourceImage: UIImage
    private let onConfirm: (UIImage) -> Void
    private let onCancel: () -> Void

    init(
        image: UIImage,
        onConfirm: @escaping (UIImage) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceImage = image
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("Use init(image:onConfirm:onCancel:)") }

    private lazy var imageView: UIImageView = {
        let view = UIImageView(image: sourceImage)
        view.contentMode = .scaleAspectFit
        view.translatesAutoresizingMaskIntoConstraints = false
        view.accessibilityLabel = String(
            localized: "photo_crop.image.accessibility",
            defaultValue: "Photo preview"
        )
        view.isAccessibilityElement = true
        return view
    }()

    private lazy var overlayView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.borderColor = UIColor.systemBlue.cgColor
        view.layer.borderWidth = 3
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        return view
    }()

    private lazy var cancelButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(String(
            localized: "photo_crop.button.cancel",
            defaultValue: "Cancel"
        ), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .title3)
        button.addTarget(self, action: #selector(cancelTapped), for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    private lazy var saveButton: UIButton = {
        let button = UIButton(type: .system)
        button.setTitle(String(
            localized: "photo_crop.button.save",
            defaultValue: "Use Photo"
        ), for: .normal)
        button.titleLabel?.font = .preferredFont(forTextStyle: .title3)
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.addTarget(self, action: #selector(confirmTapped), for: .primaryActionTriggered)
        button.translatesAutoresizingMaskIntoConstraints = false
        return button
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        view.addSubview(imageView)
        view.addSubview(overlayView)
        view.addSubview(cancelButton)
        view.addSubview(saveButton)

        let layoutGuide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: layoutGuide.topAnchor, constant: 60),
            imageView.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor, constant: -16),
            imageView.bottomAnchor.constraint(equalTo: cancelButton.topAnchor, constant: -32),

            cancelButton.leadingAnchor.constraint(equalTo: layoutGuide.leadingAnchor, constant: 24),
            cancelButton.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor, constant: -24),
            saveButton.trailingAnchor.constraint(equalTo: layoutGuide.trailingAnchor, constant: -24),
            saveButton.bottomAnchor.constraint(equalTo: layoutGuide.bottomAnchor, constant: -24),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        positionOverlay()
    }

    private func positionOverlay() {
        // Compute the on-screen rect occupied by the aspectFit image,
        // then overlay the largest centered square within that.
        let imageFrame = imageFrameWithinImageView()
        let side = min(imageFrame.width, imageFrame.height)
        let overlayOrigin = CGPoint(
            x: imageView.frame.origin.x + imageFrame.origin.x + (imageFrame.width - side) / 2,
            y: imageView.frame.origin.y + imageFrame.origin.y + (imageFrame.height - side) / 2
        )
        overlayView.frame = CGRect(origin: overlayOrigin, size: CGSize(width: side, height: side))
    }

    private func imageFrameWithinImageView() -> CGRect {
        let imageSize = sourceImage.size
        let bounds = imageView.bounds
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }

        let widthRatio = bounds.width / imageSize.width
        let heightRatio = bounds.height / imageSize.height
        let scale = min(widthRatio, heightRatio)
        let displayWidth = imageSize.width * scale
        let displayHeight = imageSize.height * scale

        return CGRect(
            x: (bounds.width - displayWidth) / 2,
            y: (bounds.height - displayHeight) / 2,
            width: displayWidth,
            height: displayHeight
        )
    }

    @objc private func confirmTapped() {
        let cropped = SquareCropper.centerSquare(sourceImage)
        onConfirm(cropped)
    }

    @objc private func cancelTapped() {
        onCancel()
    }
}
