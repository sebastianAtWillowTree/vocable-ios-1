//
//  AudioEnhanceCoordinator.swift
//  Vocable
//
//  Inserted between recording and save when the ExperimentalFeatureGate
//  is on and the device supports at least one voice enhancement. Mirrors
//  PhotoEnhanceCoordinator one-for-one so the call-site shape and the
//  test patterns stay consistent.
//

import UIKit

enum AudioEnhanceVariant {
    case original
    case voiceIsolation
}

protocol AudioEnhanceVariantPickerPresenting {
    func presentVariantPicker(
        from presenter: UIViewController,
        availableVariants: [AudioEnhanceVariant],
        onSelect: @escaping (AudioEnhanceVariant) -> Void,
        onCancel: @escaping () -> Void
    )
}

protocol VoiceIsolationPerforming {
    func performVoiceIsolation(
        on audioData: Data,
        completion: @escaping (Data?) -> Void
    )
}

final class AudioEnhanceCoordinator {

    private let gate: ExperimentalFeatureGate
    private let picker: AudioEnhanceVariantPickerPresenting
    private let isolator: VoiceIsolationPerforming
    private let progress: EnhancementProgressDisplaying

    init(
        gate: ExperimentalFeatureGate,
        picker: AudioEnhanceVariantPickerPresenting,
        isolator: VoiceIsolationPerforming,
        progress: EnhancementProgressDisplaying
    ) {
        self.gate = gate
        self.picker = picker
        self.isolator = isolator
        self.progress = progress
    }

    /// Runs the enhance step. The completion fires with the enhanced
    /// audio, the original, or nil if the caregiver cancels.
    func enhance(
        audioData: Data,
        from presenter: UIViewController,
        completion: @escaping (Data?) -> Void
    ) {
        let variants = availableVariants()
        guard !variants.isEmpty else {
            completion(audioData)
            return
        }

        picker.presentVariantPicker(
            from: presenter,
            availableVariants: [.original] + variants,
            onSelect: { [weak self] variant in
                self?.apply(variant: variant, to: audioData, from: presenter, completion: completion)
            },
            onCancel: {
                completion(nil)
            }
        )
    }

    // MARK: - Helpers

    private func availableVariants() -> [AudioEnhanceVariant] {
        gate.isVoiceEnhancementAvailable ? [.voiceIsolation] : []
    }

    private func apply(
        variant: AudioEnhanceVariant,
        to audioData: Data,
        from presenter: UIViewController,
        completion: @escaping (Data?) -> Void
    ) {
        switch variant {
        case .original:
            completion(audioData)
        case .voiceIsolation:
            let dismiss = progress.show(from: presenter, delay: 0.25, onCancel: {})
            isolator.performVoiceIsolation(on: audioData) { result in
                dismiss()
                completion(result ?? audioData)
            }
        }
    }
}
