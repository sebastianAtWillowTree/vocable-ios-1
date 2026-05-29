//
//  CartoonifyPreflightCoordinator.swift
//  Vocable
//
//  UIKit-free state machine that sits between subject lift and the
//  cartoonify applier. It owns the prompt-entry UI, kicks off the
//  PromptSubjectAligning check on Continue, and surfaces a soft
//  warning when the lifted subject and prompt look mismatched.
//
//  States:
//      enteringPrompt(prompt) — caregiver typing
//      classifying(prompt)    — aligner is running
//      misaligned(prompt, reason)
//                             — alert pending caregiver choice
//                               (Continue anyway / Edit / Cancel)
//
//  Terminal outcomes are delivered via the onContinue/onCancel
//  closures rather than held states — the VC dismisses on those.
//

import UIKit

final class CartoonifyPreflightCoordinator {

    enum State {
        case enteringPrompt(prompt: String)
        case classifying(prompt: String)
        case misaligned(prompt: String, reason: AlignmentMismatchReason)
    }

    private let sourceImage: UIImage
    private let aligner: PromptSubjectAligning
    private let onContinue: (String) -> Void
    private let onCancel: () -> Void

    /// Generation token. Bumped on cancel so a late aligner callback
    /// from before the cancel doesn't fire onContinue against a
    /// torn-down flow.
    private var generation: Int = 0
    private var didFinish = false

    var onStateChange: ((State) -> Void)?

    private(set) var state: State {
        didSet { onStateChange?(state) }
    }

    init(
        sourceImage: UIImage,
        initialPrompt: String?,
        aligner: PromptSubjectAligning,
        onContinue: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceImage = sourceImage
        self.aligner = aligner
        self.onContinue = onContinue
        self.onCancel = onCancel
        self.state = .enteringPrompt(prompt: initialPrompt ?? "")
    }

    // MARK: - Actions

    /// Caregiver typed in the prompt field. Only meaningful in
    /// .enteringPrompt; ignored once classification is in flight or a
    /// mismatch alert is up.
    func updatePrompt(_ newPrompt: String) {
        guard case .enteringPrompt = state else { return }
        state = .enteringPrompt(prompt: newPrompt)
    }

    /// Caregiver tapped Continue from the prompt screen. Trims the
    /// prompt; refuses if empty (no state change so the UI can keep
    /// the button disabled).
    func continueFromPrompt() {
        guard case .enteringPrompt(let prompt) = state else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        state = .classifying(prompt: prompt)

        let myGeneration = generation
        aligner.align(image: sourceImage, prompt: trimmed) { [weak self] result in
            guard let self else { return }
            // Drop callbacks from a previous generation (caller cancelled).
            guard self.generation == myGeneration, !self.didFinish else { return }
            self.handleAlignmentResult(result, trimmedPrompt: trimmed)
        }
    }

    /// From .misaligned — caregiver chose to proceed anyway.
    func continueAnyway() {
        guard case .misaligned(let prompt, _) = state else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        finish(continueWithPrompt: trimmed)
    }

    /// From .misaligned — caregiver chose to edit the description.
    /// Preserves the prompt; returns to .enteringPrompt with the same
    /// text so they can tweak.
    func editDescription() {
        guard case .misaligned(let prompt, _) = state else { return }
        state = .enteringPrompt(prompt: prompt)
    }

    /// Hard cancel from any state — bumps generation so a late aligner
    /// callback can't sneak through, and invokes onCancel.
    func cancel() {
        guard !didFinish else { return }
        didFinish = true
        generation &+= 1
        onCancel()
    }

    // MARK: - Internal

    private func handleAlignmentResult(_ result: AlignmentResult, trimmedPrompt: String) {
        switch result {
        case .aligned, .unknownInsufficientSignal:
            // Both proceed — we only surface the warning on a
            // confident misalignment.
            finish(continueWithPrompt: trimmedPrompt)
        case .misaligned(let reason):
            // Preserve the original (untrimmed) prompt in the state so
            // .editDescription leaves the caregiver's text intact.
            if case .classifying(let originalPrompt) = state {
                state = .misaligned(prompt: originalPrompt, reason: reason)
            } else {
                state = .misaligned(prompt: trimmedPrompt, reason: reason)
            }
        }
    }

    private func finish(continueWithPrompt prompt: String) {
        guard !didFinish else { return }
        didFinish = true
        onContinue(prompt)
    }
}
