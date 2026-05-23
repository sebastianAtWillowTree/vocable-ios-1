//
//  AudioEnhanceServices.swift
//  Vocable
//
//  Production adapters for the audio enhancement variants.
//
//  - AlertAudioVariantPicker  : UIAlertController-based variant chooser
//  - AVEngineVoiceIsolator    : iOS 17+, placeholder — the protocol
//    seam is in place but the real adapter needs AVAudioEngine
//    voice-processing post-processing work that's larger than this
//    PR. Returns nil so the coordinator falls back to Original.
//

import UIKit

// MARK: - Variant picker

struct AlertAudioVariantPicker: AudioEnhanceVariantPickerPresenting {

    func presentVariantPicker(
        from presenter: UIViewController,
        availableVariants: [AudioEnhanceVariant],
        onSelect: @escaping (AudioEnhanceVariant) -> Void,
        onCancel: @escaping () -> Void
    ) {
        let title = String(
            localized: "audio_enhance.alert.title",
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
                    localized: "audio_enhance.alert.cancel",
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

    private static func title(for variant: AudioEnhanceVariant) -> String {
        switch variant {
        case .original:
            return String(localized: "audio_enhance.variant.original", defaultValue: "Original")
        case .voiceIsolation:
            return String(localized: "audio_enhance.variant.voice_isolation", defaultValue: "Voice Isolation")
        }
    }
}

// MARK: - Voice isolation (iOS 17+)

/// Placeholder for AVAudioEngine-based voice isolation. The seam is in
/// place so the coordinator and call sites can land now; a future
/// ticket replaces this with a real implementation that re-encodes
/// the recording through voice-processing-enabled input.
final class AVEngineVoiceIsolator: VoiceIsolationPerforming {

    func performVoiceIsolation(
        on audioData: Data,
        completion: @escaping (Data?) -> Void
    ) {
        // Returning nil makes the coordinator fall back to the original
        // recording, so the caregiver still gets a usable card.
        completion(nil)
    }
}
