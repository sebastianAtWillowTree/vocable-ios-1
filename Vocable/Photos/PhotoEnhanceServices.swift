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

#if canImport(ImagePlayground)
import ImagePlayground
#endif

/// Production CartoonifyApplying.
///
/// On iOS 18.1+ when ImagePlaygroundViewController.isAvailable is true,
/// presents Apple's system Image Playground UI with the source image
/// pre-loaded and the caregiver's previous prompt (if any) supplied as
/// an `.extracted(from:)` concept. Apple's UI handles the full
/// generate + iterate + accept experience.
///
/// On unsupported devices (older iOS, Apple Intelligence disabled,
/// non-AI-capable hardware) falls back to the custom describe →
/// generate → review flow, which will show
/// "Cartoon style isn't available on this device" rather than
/// silently saving the original — no UI lies.
final class CartoonifyApplier: CartoonifyApplying {

    private let generator: CartoonGenerating
    private var activeDelegate: AnyObject?

    init(generator: CartoonGenerating = ImagePlaygroundCartoonGenerator()) {
        self.generator = generator
    }

    func performCartoonify(
        on image: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyOutcome?) -> Void
    ) {
        #if canImport(ImagePlayground)
        if #available(iOS 18.1, *), ImagePlaygroundViewController.isAvailable {
            presentSystemImagePlayground(
                on: image,
                initialPrompt: initialPrompt,
                from: presenter,
                completion: completion
            )
            return
        }
        #endif

        // Fallback: custom flow (which currently always surfaces the
        // honest "unavailable" error). Preserves the flow seam so a
        // future non-Apple generator can be slotted in here.
        presentCustomFlow(
            on: image,
            initialPrompt: initialPrompt,
            from: presenter,
            completion: completion
        )
    }

    // MARK: - System Image Playground (iOS 18.1+)

    #if canImport(ImagePlayground)
    @available(iOS 18.1, *)
    private func presentSystemImagePlayground(
        on image: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyOutcome?) -> Void
    ) {
        let vc = ImagePlaygroundViewController()
        vc.sourceImage = image
        if let trimmed = initialPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !trimmed.isEmpty {
            vc.concepts = [.extracted(from: trimmed)]
        }
        // Cartoonify is for objects, not people. Image Playground's
        // face/identity personalization (Genmoji-style) tries to pin
        // a detected face to the user's contacts and routes through a
        // different generation path. Disable it explicitly so the
        // caregiver's "blue sippy cup" prompt isn't hijacked by a face
        // in the background of the photo. iOS 18.4+ only — older
        // releases inherit the system default.
        if #available(iOS 18.4, *) {
            vc.personalizationPolicy = .disabled
        }

        // Delegate holds the completion closure and the prompt the
        // caregiver supplied; on result it loads the URL into a UIImage
        // and bridges back through CartoonifyOutcome.
        let delegate = ImagePlaygroundDelegateAdapter(
            initialPrompt: initialPrompt,
            completion: { [weak self] outcome in
                self?.activeDelegate = nil
                presenter.dismiss(animated: true) {
                    completion(outcome)
                }
            }
        )
        vc.delegate = delegate
        // Retain through presentation — the VC only holds the delegate weakly.
        activeDelegate = delegate

        presenter.present(vc, animated: true)
    }
    #endif

    // MARK: - Custom-flow fallback

    private func presentCustomFlow(
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

#if canImport(ImagePlayground)
@available(iOS 18.1, *)
private final class ImagePlaygroundDelegateAdapter: NSObject, ImagePlaygroundViewController.Delegate {

    private let initialPrompt: String?
    private let completion: (CartoonifyOutcome?) -> Void
    private var didDeliver = false

    init(initialPrompt: String?, completion: @escaping (CartoonifyOutcome?) -> Void) {
        self.initialPrompt = initialPrompt
        self.completion = completion
    }

    func imagePlaygroundViewController(
        _ imagePlaygroundViewController: ImagePlaygroundViewController,
        didCreateImageAt imageURL: URL
    ) {
        guard !didDeliver else { return }
        didDeliver = true

        guard let data = try? Data(contentsOf: imageURL),
              let image = UIImage(data: data) else {
            completion(nil)
            return
        }
        // Best-effort cleanup — Apple writes a temp file we don't need
        // to keep around once we've decoded it.
        try? FileManager.default.removeItem(at: imageURL)

        let prompt = (initialPrompt ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        completion(CartoonifyOutcome(image: image, prompt: prompt))
    }

    func imagePlaygroundViewControllerDidCancel(
        _ imagePlaygroundViewController: ImagePlaygroundViewController
    ) {
        guard !didDeliver else { return }
        didDeliver = true
        completion(nil)
    }
}
#endif

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
