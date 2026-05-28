//
//  CartoonGenerating.swift
//  Vocable
//
//  Protocol seam for generating a stylized cartoon variant of a
//  source image, guided by a caregiver-supplied description.
//
//  The production adapter (ImagePlayground) is iOS 18.1+ + AI-device
//  gated. On unsupported devices the call returns
//  CartoonGenerationError.unavailableOnThisDevice and the call site
//  surfaces an honest "cartoon style isn't available here" message
//  rather than silently falling back (the brutal review flagged the
//  prior placeholder pattern for this kind of UI lie).
//

import UIKit

protocol CartoonGenerating: AnyObject {
    @discardableResult
    func generate(
        sourceImage: UIImage,
        prompt: String,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) -> CartoonGenerationToken
}

/// Cancellation handle returned by `generate`. Calling `cancel()`
/// prevents the completion from firing with a generated image. The
/// production implementation is expected to abort the in-flight
/// request as well.
final class CartoonGenerationToken {
    /// `internal` so generator implementations in other files within
    /// the module can check it. External callers should mutate only
    /// through `cancel()`.
    private(set) var isCancelled = false
    func cancel() { isCancelled = true }
}

enum CartoonGenerationError: Error {
    case unavailableOnThisDevice
    case promptEmpty
    case cancelled
    case generationFailed(underlying: Error?)
}
