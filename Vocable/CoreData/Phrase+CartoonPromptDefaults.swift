//
//  Phrase+CartoonPromptDefaults.swift
//  Vocable
//
//  Computes the initial prompt to seed the cartoonify flow with.
//  Order of preference:
//   1. The previously-saved cartoonPrompt (if non-empty)
//   2. A localized default derived from the phrase's utterance
//   3. nil (nothing useful to seed with)
//
//  Whitespace-only prompts are treated as empty so a caregiver
//  who clears the field and saves doesn't see "   " next time.
//

import Foundation

extension Phrase {

    /// Initial prompt to seed the cartoonify flow's description field.
    /// The caregiver can edit it before generating.
    var initialCartoonPrompt: String? {
        if let saved = cartoonPrompt?.trimmingCharacters(in: .whitespacesAndNewlines),
           !saved.isEmpty {
            return saved
        }
        if let utteranceValue = utterance?.trimmingCharacters(in: .whitespacesAndNewlines),
           !utteranceValue.isEmpty {
            // The catalog value carries a %@ placeholder; substitute via
            // String(format:) so the utterance lands correctly in both
            // the development-language default and any translation.
            let template = String(
                localized: "cartoonify.default_prompt.template",
                defaultValue: "a colorful, high contrast, child friendly cartoon illustration of %@"
            )
            return String(format: template, utteranceValue)
        }
        return nil
    }
}
