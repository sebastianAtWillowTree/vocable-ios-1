//
//  PhotoEnhanceCoordinator.swift
//  Vocable
//
//  Inserted between crop and save when experimental enhancements
//  are enabled and at least one variant is supported by the device.
//
//  The coordinator branches the flow based on the ExperimentalFeatureGate
//  and routes the caregiver's choice through protocol seams so the
//  Vision and Image Playground integrations can be swapped for fakes
//  in tests.
//

import UIKit

enum PhotoEnhanceVariant {
    case original
    case subjectLift
    case cartoonify
}

/// Result of a cartoonify variant: the rendered image plus the
/// caregiver-supplied prompt that produced it (saved on Phrase so
/// re-entry can pre-fill the description).
struct CartoonifyOutcome {
    let image: UIImage
    let prompt: String
}

protocol CartoonifyApplying {
    func performCartoonify(
        on image: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyOutcome?) -> Void
    )
}

protocol PhotoEnhanceVariantPickerPresenting {
    func presentVariantPicker(
        from presenter: UIViewController,
        original: UIImage,
        availableVariants: [PhotoEnhanceVariant],
        onSelect: @escaping (PhotoEnhanceVariant) -> Void,
        onCancel: @escaping () -> Void
    )
}

protocol SubjectLiftPerforming {
    func performSubjectLift(
        on image: UIImage,
        completion: @escaping (UIImage?) -> Void
    )
}

protocol EnhancementProgressDisplaying {
    /// Shows an indeterminate progress UI after `delay` if the work
    /// has not completed. Returns a closure that dismisses it.
    func show(
        from presenter: UIViewController,
        delay: TimeInterval,
        onCancel: @escaping () -> Void
    ) -> () -> Void
}

/// Outcome of an enhance step: the resulting image plus an
/// optional cartoon prompt if the user went through the cartoonify
/// variant. Photo callers that care about the prompt persist it
/// on the Phrase; other callers can ignore it.
struct PhotoEnhanceOutcome {
    let image: UIImage
    let cartoonPrompt: String?
}

final class PhotoEnhanceCoordinator {

    private let gate: ExperimentalFeatureGate
    private let picker: PhotoEnhanceVariantPickerPresenting
    private let subjectLifter: SubjectLiftPerforming
    /// Optional. When nil, the .cartoonify variant is not offered.
    /// Category authoring passes nil; phrase authoring passes a real
    /// CartoonifyApplier.
    private let cartoonifyApplier: CartoonifyApplying?
    /// Optional. When non-nil AND cartoonifyApplier is non-nil, the
    /// .cartoonify variant runs a preflight prompt-vs-subject check
    /// between subject lift and the applier. When nil, the applier is
    /// invoked directly (legacy path / test configurations).
    private let preflightPresenter: CartoonifyPreflightPresenting?
    private let progress: EnhancementProgressDisplaying

    init(
        gate: ExperimentalFeatureGate,
        picker: PhotoEnhanceVariantPickerPresenting,
        subjectLifter: SubjectLiftPerforming,
        cartoonifyApplier: CartoonifyApplying?,
        preflightPresenter: CartoonifyPreflightPresenting? = nil,
        progress: EnhancementProgressDisplaying
    ) {
        self.gate = gate
        self.picker = picker
        self.subjectLifter = subjectLifter
        self.cartoonifyApplier = cartoonifyApplier
        self.preflightPresenter = preflightPresenter
        self.progress = progress
    }

    /// Runs the enhance step. The completion fires with an outcome
    /// (image + optional cartoon prompt) or nil if cancelled.
    func enhance(
        image: UIImage,
        initialCartoonPrompt: String? = nil,
        from presenter: UIViewController,
        completion: @escaping (PhotoEnhanceOutcome?) -> Void
    ) {
        let variants = availableVariants()
        // Bypass entirely when experimental is disabled or device has
        // no variants beyond Original. The caller continues with the
        // un-enhanced image and no prompt.
        guard !variants.isEmpty else {
            completion(PhotoEnhanceOutcome(image: image, cartoonPrompt: nil))
            return
        }

        picker.presentVariantPicker(
            from: presenter,
            original: image,
            availableVariants: [.original] + variants,
            onSelect: { [weak self] variant in
                self?.apply(
                    variant: variant,
                    to: image,
                    initialCartoonPrompt: initialCartoonPrompt,
                    from: presenter,
                    completion: completion
                )
            },
            onCancel: {
                completion(nil)
            }
        )
    }

    // MARK: - Helpers

    private func availableVariants() -> [PhotoEnhanceVariant] {
        var result: [PhotoEnhanceVariant] = []
        if gate.isSubjectLiftAvailable { result.append(.subjectLift) }
        if cartoonifyApplier != nil && gate.isImagePlaygroundAvailable {
            result.append(.cartoonify)
        }
        return result
    }

    private func apply(
        variant: PhotoEnhanceVariant,
        to image: UIImage,
        initialCartoonPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (PhotoEnhanceOutcome?) -> Void
    ) {
        switch variant {
        case .original:
            completion(PhotoEnhanceOutcome(image: image, cartoonPrompt: nil))
        case .subjectLift:
            runWithProgress(presenter: presenter) { [subjectLifter] done in
                subjectLifter.performSubjectLift(on: image) { result in
                    done()
                    completion(PhotoEnhanceOutcome(image: result ?? image, cartoonPrompt: nil))
                }
            }
        case .cartoonify:
            guard let applier = cartoonifyApplier else {
                // Should be impossible — availableVariants() filtered this out.
                completion(PhotoEnhanceOutcome(image: image, cartoonPrompt: nil))
                return
            }

            // Chain: preflight (if enabled) → cartoonify → post-lift.
            //
            // Lifting AFTER cartoonify is intentional. Image Playground
            // works better when it sees the whole scene (it uses
            // surrounding context to model the subject); running the
            // lift on the original would strip that context. We then
            // lift the cartoon output to produce a clean cartoon
            // subject on a flat canvas — the final asset stored on the
            // phrase.
            //
            // • Preflight: classifies the SOURCE image so the caregiver
            //   gets a warning if their prompt doesn't match what's in
            //   the photo. Skipped when no preflightPresenter injected.
            // • Cartoonify: runs on the source image, with the
            //   caregiver-confirmed prompt.
            // • Post-lift: extracts the cartoon subject onto a flat
            //   canvas. Opportunistic — falls back to the cartoon as-is
            //   if the lift returns nil / iOS doesn't support it.
            let liftCartoonThenComplete: (UIImage, String) -> Void = { [gate, subjectLifter] cartoonImage, confirmedPrompt in
                guard gate.isSubjectLiftAvailable else {
                    completion(PhotoEnhanceOutcome(image: cartoonImage, cartoonPrompt: confirmedPrompt))
                    return
                }
                self.runWithProgress(presenter: presenter) { done in
                    subjectLifter.performSubjectLift(on: cartoonImage) { liftedCartoon in
                        done()
                        completion(PhotoEnhanceOutcome(
                            image: liftedCartoon ?? cartoonImage,
                            cartoonPrompt: confirmedPrompt
                        ))
                    }
                }
            }

            let runApplier: (String?) -> Void = { confirmedPrompt in
                applier.performCartoonify(
                    on: image,
                    initialPrompt: confirmedPrompt,
                    from: presenter
                ) { outcome in
                    guard let outcome else {
                        // Caregiver cancelled the cartoonify flow — bubble up
                        // a nil completion so the caller knows to abandon save.
                        completion(nil)
                        return
                    }
                    liftCartoonThenComplete(outcome.image, outcome.prompt)
                }
            }

            if let preflightPresenter {
                preflightPresenter.presentPreflight(
                    sourceImage: image,
                    initialPrompt: initialCartoonPrompt,
                    from: presenter
                ) { outcome in
                    guard let outcome else {
                        // Cancelled at the preflight step — abandon the
                        // whole enhance flow.
                        completion(nil)
                        return
                    }
                    runApplier(outcome.confirmedPrompt)
                }
            } else {
                runApplier(initialCartoonPrompt)
            }
        }
    }

    private func runWithProgress(
        presenter: UIViewController,
        body: @escaping (_ done: @escaping () -> Void) -> Void
    ) {
        let dismiss = progress.show(from: presenter, delay: 0.25, onCancel: {})
        body {
            dismiss()
        }
    }
}
