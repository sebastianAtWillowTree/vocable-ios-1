//
//  CartoonStylePromptAugmenter.swift
//  Vocable
//
//  Pure-function helper that decorates a caregiver-typed prompt with
//  style cues before it goes to the image generator. AAC users benefit
//  from high-contrast imagery, so we suffix "high contrast" so Image
//  Playground biases that way.
//
//  Important:
//  - The caregiver's typed prompt is preserved verbatim in the UI and
//    on Phrase.cartoonPrompt. This augmentation is only what we pass
//    to the generator's `.extracted(from:)` concept.
//  - Idempotent: caregivers who already typed "high contrast" don't
//    get a duplicate suffix.
//

import Foundation

enum CartoonStylePromptAugmenter {

    /// English style suffix appended to the caregiver's prompt for
    /// Image Playground. Apple Intelligence is currently English-only
    /// so we don't localize this — the prompt itself stays in whatever
    /// language the caregiver typed.
    static let highContrastHint = "high contrast"

    /// Returns `prompt` with the high-contrast hint appended, unless
    /// the prompt is empty/whitespace or already contains the hint.
    /// Trims surrounding whitespace.
    static func augment(_ prompt: String) -> String {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.lowercased().contains(highContrastHint) {
            return trimmed
        }
        return "\(trimmed), \(highContrastHint)"
    }
}
