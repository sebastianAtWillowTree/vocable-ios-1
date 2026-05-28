//
//  CartoonifyFlowCoordinator.swift
//  Vocable
//
//  Drives the multi-step caregiver-described cartoonify flow:
//      describing → generating → reviewing → (refine ↺ | save | cancel)
//
//  UIKit-free state machine; the VC subscribes to state changes and
//  renders. Errors from the generator (including
//  CartoonGenerationError.unavailableOnThisDevice) surface back to
//  the .describing state with a human-readable message — no UI lies.
//

import UIKit

final class CartoonifyFlowCoordinator {

    enum State {
        case describing(prompt: String, errorMessage: String?)
        case generating(prompt: String)
        case reviewing(result: UIImage, prompt: String)
    }

    private let sourceImage: UIImage
    private let generator: CartoonGenerating
    private let onSave: (UIImage, String) -> Void
    private let onCancel: () -> Void

    private var activeToken: CartoonGenerationToken?

    /// Fires on every state change. The VC subscribes to render.
    var onStateChange: ((State) -> Void)?

    private(set) var state: State {
        didSet { onStateChange?(state) }
    }

    init(
        sourceImage: UIImage,
        initialPrompt: String?,
        generator: CartoonGenerating,
        onSave: @escaping (UIImage, String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.sourceImage = sourceImage
        self.generator = generator
        self.onSave = onSave
        self.onCancel = onCancel
        self.state = .describing(prompt: initialPrompt ?? "", errorMessage: nil)
    }

    // MARK: - Actions

    /// Caregiver typed into the description field.
    func updatePrompt(_ newPrompt: String) {
        guard case .describing(_, let err) = state else { return }
        state = .describing(prompt: newPrompt, errorMessage: err)
    }

    /// "Generate" button tapped. Ignored if the prompt is empty/whitespace.
    func generate() {
        guard case .describing(let prompt, _) = state else { return }
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        state = .generating(prompt: trimmed)
        activeToken = generator.generate(
            sourceImage: sourceImage,
            prompt: trimmed
        ) { [weak self] result in
            self?.handleGenerationResult(result)
        }
    }

    /// Cancel from the .generating state — aborts the in-flight request
    /// and returns to .describing with the prompt preserved.
    func cancelGeneration() {
        activeToken?.cancel()
        activeToken = nil
        if case .generating(let prompt) = state {
            state = .describing(prompt: prompt, errorMessage: nil)
        }
    }

    /// "Refine" from .reviewing — go back to editing the description.
    func refine() {
        guard case .reviewing(_, let prompt) = state else { return }
        state = .describing(prompt: prompt, errorMessage: nil)
    }

    /// "Use this" from .reviewing — invokes onSave with the chosen
    /// result and the prompt that produced it.
    func confirm() {
        guard case .reviewing(let image, let prompt) = state else { return }
        onSave(image, prompt)
    }

    /// Hard cancel — aborts any in-flight request and invokes onCancel.
    func cancel() {
        activeToken?.cancel()
        activeToken = nil
        onCancel()
    }

    // MARK: - Generation result

    private func handleGenerationResult(_ result: Result<UIImage, Error>) {
        // If the user moved on (e.g., cancelled) before the result
        // arrived, ignore the stale callback.
        guard case .generating(let prompt) = state else { return }

        switch result {
        case .success(let image):
            state = .reviewing(result: image, prompt: prompt)
        case .failure(let error):
            state = .describing(
                prompt: prompt,
                errorMessage: Self.errorMessage(for: error)
            )
        }
    }

    private static func errorMessage(for error: Error) -> String {
        if let cartoonError = error as? CartoonGenerationError {
            switch cartoonError {
            case .unavailableOnThisDevice:
                return String(
                    localized: "cartoonify.error.unavailable",
                    defaultValue: "Cartoon style isn't available on this device."
                )
            case .promptEmpty:
                return String(
                    localized: "cartoonify.error.empty_prompt",
                    defaultValue: "Please type a description."
                )
            case .cancelled:
                return String(
                    localized: "cartoonify.error.cancelled",
                    defaultValue: "Cancelled."
                )
            case .generationFailed:
                return String(
                    localized: "cartoonify.error.failed",
                    defaultValue: "Couldn't generate a cartoon. Try a different description."
                )
            }
        }
        return String(
            localized: "cartoonify.error.unknown",
            defaultValue: "Something went wrong. Please try again."
        )
    }
}
