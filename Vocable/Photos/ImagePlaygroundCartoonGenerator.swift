//
//  ImagePlaygroundCartoonGenerator.swift
//  Vocable
//
//  Production adapter for prompt-driven cartoon generation. Uses
//  Apple's ImagePlayground framework, which requires iOS 18.1+ on
//  an Apple-Intelligence-capable device.
//
//  Current state: protocol seam in place; ImagePlayground SDK
//  integration deferred until the project pins an iOS 18.1+ SDK.
//  Returns CartoonGenerationError.unavailableOnThisDevice so the
//  flow VC presents an honest "not available" message — explicitly
//  NOT silently falling back to the original image (the prior
//  placeholder pattern that the brutal review called out as a
//  "UI lie").
//

import UIKit

final class ImagePlaygroundCartoonGenerator: CartoonGenerating {

    @discardableResult
    func generate(
        sourceImage: UIImage,
        prompt: String,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) -> CartoonGenerationToken {
        let token = CartoonGenerationToken()

        let trimmedPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedPrompt.isEmpty else {
            DispatchQueue.main.async {
                completion(.failure(CartoonGenerationError.promptEmpty))
            }
            return token
        }

        // TODO: integrate Apple ImagePlayground (ImageCreator /
        // ImagePlaygroundViewController) once the SDK is pinned. The
        // upgrade should:
        //   1. Honor token.isCancelled at every async boundary.
        //   2. Pass `prompt` as the .text concept.
        //   3. Pass `sourceImage` as a .image style source.
        //   4. Return .success(image) on completion, or
        //      .failure(.generationFailed(underlying:)) on error.
        DispatchQueue.main.async {
            if token.isCancelled { return }
            completion(.failure(CartoonGenerationError.unavailableOnThisDevice))
        }

        return token
    }
}
