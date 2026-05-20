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
    case stylize
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

protocol ImagePlaygroundStylizing {
    func performStylize(
        on image: UIImage,
        from presenter: UIViewController,
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

final class PhotoEnhanceCoordinator {

    private let gate: ExperimentalFeatureGate
    private let picker: PhotoEnhanceVariantPickerPresenting
    private let subjectLifter: SubjectLiftPerforming
    private let stylizer: ImagePlaygroundStylizing
    private let progress: EnhancementProgressDisplaying

    init(
        gate: ExperimentalFeatureGate,
        picker: PhotoEnhanceVariantPickerPresenting,
        subjectLifter: SubjectLiftPerforming,
        stylizer: ImagePlaygroundStylizing,
        progress: EnhancementProgressDisplaying
    ) {
        self.gate = gate
        self.picker = picker
        self.subjectLifter = subjectLifter
        self.stylizer = stylizer
        self.progress = progress
    }

    /// Runs the enhance step. The completion fires with the enhanced
    /// image, the original, or nil if cancelled.
    func enhance(
        image: UIImage,
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        let variants = availableVariants()
        // Bypass entirely when experimental is disabled or device has
        // no variants beyond Original. The caller will continue with
        // the un-enhanced image.
        guard !variants.isEmpty else {
            completion(image)
            return
        }

        picker.presentVariantPicker(
            from: presenter,
            original: image,
            availableVariants: [.original] + variants,
            onSelect: { [weak self] variant in
                self?.apply(variant: variant, to: image, from: presenter, completion: completion)
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
        if gate.isImagePlaygroundAvailable { result.append(.stylize) }
        return result
    }

    private func apply(
        variant: PhotoEnhanceVariant,
        to image: UIImage,
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        switch variant {
        case .original:
            completion(image)
        case .subjectLift:
            runWithProgress(presenter: presenter) { [subjectLifter] done in
                subjectLifter.performSubjectLift(on: image) { result in
                    done()
                    completion(result ?? image)
                }
            }
        case .stylize:
            runWithProgress(presenter: presenter) { [stylizer] done in
                stylizer.performStylize(on: image, from: presenter) { result in
                    done()
                    completion(result ?? image)
                }
            }
        }
    }

    private func runWithProgress(
        presenter: UIViewController,
        body: @escaping (_ done: @escaping () -> Void) -> Void
    ) {
        let dismiss = progress.show(from: presenter, delay: 0.25, onCancel: {
            // Cancel handler — the body's own completion will dismiss
            // again, but multiple invocations are safe.
        })
        body {
            dismiss()
        }
    }
}
