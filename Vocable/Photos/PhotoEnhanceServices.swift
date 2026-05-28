//
//  PhotoEnhanceServices.swift
//  Vocable
//
//  Production adapters for the photo enhancement variants. Each
//  service is OS-version gated; when the runtime can't support it,
//  the completion is invoked with nil so the coordinator falls back
//  to the original image.
//
//  - VisionSubjectLiftService    : iOS 17+, VNGenerateForegroundInstanceMaskRequest
//  - ImagePlaygroundStylizer     : iOS 18.1+, ImagePlayground (placeholder until SDK ships)
//  - AlertVariantPicker          : UIAlertController-based variant chooser
//  - AlertEnhancementProgress    : minimal progress alert with a cancel button
//

import UIKit
import Vision
import CoreImage

// MARK: - Variant picker

struct AlertVariantPicker: PhotoEnhanceVariantPickerPresenting {

    func presentVariantPicker(
        from presenter: UIViewController,
        original: UIImage,
        availableVariants: [PhotoEnhanceVariant],
        onSelect: @escaping (PhotoEnhanceVariant) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let title = String(
            localized: "photo_enhance.alert.title",
            defaultValue: "Choose a style"
        )

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        for variant in availableVariants {
            alert.addAction(
                UIAlertAction(title: Self.title(for: variant), style: .default) { _ in
                    onSelect(variant)
                }
            )
        }
        alert.addAction(
            UIAlertAction(
                title: String(
                    localized: "photo_enhance.alert.cancel",
                    defaultValue: "Cancel"
                ),
                style: .cancel
            ) { _ in onCancel() }
        )

        alert.popoverPresentationController?.sourceView = presenter.view
        alert.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 0,
            height: 0
        )

        presenter.present(alert, animated: true)
    }

    private static func title(for variant: PhotoEnhanceVariant) -> String {
        switch variant {
        case .original:
            return String(localized: "photo_enhance.variant.original", defaultValue: "Original")
        case .subjectLift:
            return String(localized: "photo_enhance.variant.subject_lift", defaultValue: "Subject Lift")
        case .cartoonify:
            return String(localized: "photo_enhance.variant.cartoonify", defaultValue: "Cartoon (Custom)")
        }
    }
}

// MARK: - Subject lift via Vision (iOS 17+)

final class VisionSubjectLiftService: SubjectLiftPerforming {

    func performSubjectLift(
        on image: UIImage,
        completion: @escaping (UIImage?) -> Void
    ) {
        if #available(iOS 17, *) {
            performWithVision(image: image, completion: completion)
        } else {
            completion(nil)
        }
    }

    @available(iOS 17, *)
    private func performWithVision(
        image: UIImage,
        completion: @escaping (UIImage?) -> Void
    ) {
        guard let cgImage = image.cgImage else {
            completion(nil)
            return
        }

        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNGenerateForegroundInstanceMaskRequest()

            do {
                try handler.perform([request])
                guard let result = request.results?.first else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let masked = try result.generateMaskedImage(
                    ofInstances: result.allInstances,
                    from: handler,
                    croppedToInstancesExtent: true
                )
                let outputCI = CIImage(cvPixelBuffer: masked)
                let context = CIContext(options: nil)
                guard let outputCG = context.createCGImage(outputCI, from: outputCI.extent) else {
                    DispatchQueue.main.async { completion(nil) }
                    return
                }
                let composited = Self.compositeOnSystemGray(
                    foreground: UIImage(cgImage: outputCG),
                    boundingSize: image.size
                )
                DispatchQueue.main.async { completion(composited) }
            } catch {
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    private static func compositeOnSystemGray(
        foreground: UIImage,
        boundingSize: CGSize
    ) -> UIImage {
        // Recenter the extracted subject inside a square canvas filled
        // with system gray. Canvas side = max(boundingSize.width/height).
        let side = max(boundingSize.width, boundingSize.height, max(foreground.size.width, foreground.size.height))
        let canvasSize = CGSize(width: side, height: side)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            UIColor.systemGray.setFill()
            ctx.fill(CGRect(origin: .zero, size: canvasSize))
            let drawSize = foreground.size
            let originX = (canvasSize.width - drawSize.width) / 2
            let originY = (canvasSize.height - drawSize.height) / 2
            foreground.draw(in: CGRect(origin: CGPoint(x: originX, y: originY), size: drawSize))
        }
    }
}

// MARK: - Cartoonify applier (iOS 18.1+, caregiver-described)

/// Production CartoonifyApplying — constructs a CartoonifyFlowCoordinator
/// backed by ImagePlaygroundCartoonGenerator and presents the multi-step
/// flow VC. When the user accepts a result, the outcome carries both
/// the generated image AND the prompt that produced it so callers can
/// persist the prompt on the Phrase for future re-entry.
final class CartoonifyApplier: CartoonifyApplying {

    private let generator: CartoonGenerating

    init(generator: CartoonGenerating = ImagePlaygroundCartoonGenerator()) {
        self.generator = generator
    }

    func performCartoonify(
        on image: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyOutcome?) -> Void
    ) {
        var flowVC: UIViewController?

        let coordinator = CartoonifyFlowCoordinator(
            sourceImage: image,
            initialPrompt: initialPrompt,
            generator: generator,
            onSave: { resultImage, prompt in
                flowVC?.dismiss(animated: true) {
                    completion(CartoonifyOutcome(image: resultImage, prompt: prompt))
                }
            },
            onCancel: {
                flowVC?.dismiss(animated: true) {
                    completion(nil)
                }
            }
        )
        let vc = CartoonifyFlowViewController(coordinator: coordinator)
        flowVC = vc
        presenter.present(vc, animated: true)
    }
}

// MARK: - Enhancement progress

final class AlertEnhancementProgress: EnhancementProgressDisplaying {

    private weak var presented: UIAlertController?

    func show(
        from presenter: UIViewController,
        delay: TimeInterval,
        onCancel: @escaping () -> Void
    ) -> () -> Void {
        var didFinish = false

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self, weak presenter] in
            guard let self, let presenter, !didFinish else { return }
            let alert = UIAlertController(
                title: String(
                    localized: "photo_enhance.progress.title",
                    defaultValue: "Enhancing photo…"
                ),
                message: nil,
                preferredStyle: .alert
            )
            alert.addAction(
                UIAlertAction(
                    title: String(
                        localized: "photo_enhance.progress.cancel",
                        defaultValue: "Cancel"
                    ),
                    style: .cancel
                ) { _ in onCancel() }
            )
            self.presented = alert
            presenter.present(alert, animated: true)
        }

        return { [weak self] in
            didFinish = true
            self?.presented?.dismiss(animated: true)
            self?.presented = nil
        }
    }
}
