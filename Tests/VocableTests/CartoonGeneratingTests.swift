//
//  CartoonGeneratingTests.swift
//  VocableTests
//
//  Exercises the contract surface — protocol callers can rely on
//  empty-prompt and cancellation semantics, plus the production
//  adapter's honest "unavailable" behavior on this build.
//

import XCTest
import UIKit
@testable import Vocable

final class CartoonGeneratingTests: XCTestCase {

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
        return renderer.image { ctx in
            UIColor.orange.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }

    // MARK: - Production adapter (placeholder behavior)

    func test_imagePlaygroundGenerator_emptyPrompt_failsWith_promptEmpty() {
        let generator = ImagePlaygroundCartoonGenerator()
        let exp = expectation(description: "completion fires")
        _ = generator.generate(sourceImage: makeImage(), prompt: "   ") { result in
            switch result {
            case .success:
                XCTFail("Empty prompt should not produce a generated image")
            case .failure(let error):
                if case CartoonGenerationError.promptEmpty = error {
                    // OK
                } else {
                    XCTFail("Expected promptEmpty, got \(error)")
                }
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func test_imagePlaygroundGenerator_validPrompt_failsWith_unavailableOnThisDevice() {
        // Until ImagePlayground SDK integration lands, the production
        // adapter is expected to fail honestly rather than silently
        // returning the source image. This pins that contract.
        let generator = ImagePlaygroundCartoonGenerator()
        let exp = expectation(description: "completion fires")
        _ = generator.generate(sourceImage: makeImage(), prompt: "a friendly red cup") { result in
            switch result {
            case .success:
                XCTFail("Adapter should not produce a generated image until SDK integration")
            case .failure(let error):
                if case CartoonGenerationError.unavailableOnThisDevice = error {
                    // OK
                } else {
                    XCTFail("Expected unavailableOnThisDevice, got \(error)")
                }
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1)
    }

    func test_token_cancel_preventsCompletion() {
        let generator = ImagePlaygroundCartoonGenerator()
        let shouldNotFire = expectation(description: "completion not fired")
        shouldNotFire.isInverted = true

        let token = generator.generate(sourceImage: makeImage(), prompt: "anything") { _ in
            shouldNotFire.fulfill()
        }
        token.cancel()

        wait(for: [shouldNotFire], timeout: 0.5)
    }

    // MARK: - Protocol contract via a fake

    func test_protocol_isInhabitedBy_imagePlaygroundGenerator() {
        let generator: CartoonGenerating = ImagePlaygroundCartoonGenerator()
        let token = generator.generate(sourceImage: makeImage(), prompt: "noop") { _ in }
        token.cancel()
    }
}
