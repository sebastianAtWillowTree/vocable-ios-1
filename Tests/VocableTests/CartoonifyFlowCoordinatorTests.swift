//
//  CartoonifyFlowCoordinatorTests.swift
//  VocableTests
//

import XCTest
import UIKit
@testable import Vocable

final class CartoonifyFlowCoordinatorTests: XCTestCase {

    private var generator: SpyGenerator!
    private var sourceImage: UIImage!
    private var savedResults: [(UIImage, String)] = []
    private var cancelInvocations: Int = 0

    override func setUpWithError() throws {
        try super.setUpWithError()
        generator = SpyGenerator()
        sourceImage = solidImage(.red)
        savedResults = []
        cancelInvocations = 0
    }

    override func tearDownWithError() throws {
        generator = nil
        sourceImage = nil
        try super.tearDownWithError()
    }

    // MARK: - Initial state

    func test_initial_stateIsDescribing_withEmptyPrompt_byDefault() {
        let coordinator = makeCoordinator(initialPrompt: nil)
        guard case .describing(let prompt, let err) = coordinator.state else {
            XCTFail("Expected .describing"); return
        }
        XCTAssertEqual(prompt, "")
        XCTAssertNil(err)
    }

    func test_initial_stateIsDescribing_withInitialPrompt_whenProvided() {
        let coordinator = makeCoordinator(initialPrompt: "a friendly cup")
        guard case .describing(let prompt, _) = coordinator.state else {
            XCTFail("Expected .describing"); return
        }
        XCTAssertEqual(prompt, "a friendly cup")
    }

    // MARK: - updatePrompt

    func test_updatePrompt_changesPrompt_inDescribingState() {
        let coordinator = makeCoordinator(initialPrompt: nil)
        coordinator.updatePrompt("a red ball")
        guard case .describing(let prompt, _) = coordinator.state else {
            XCTFail("Expected .describing"); return
        }
        XCTAssertEqual(prompt, "a red ball")
    }

    func test_updatePrompt_ignored_inGeneratingState() {
        let coordinator = makeCoordinator(initialPrompt: "first")
        coordinator.generate()
        coordinator.updatePrompt("second")
        guard case .generating(let prompt) = coordinator.state else {
            XCTFail("Expected still .generating"); return
        }
        XCTAssertEqual(prompt, "first")
    }

    // MARK: - generate

    func test_generate_transitionsToGenerating_andInvokesGenerator() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()
        guard case .generating(let prompt) = coordinator.state else {
            XCTFail("Expected .generating"); return
        }
        XCTAssertEqual(prompt, "a cup")
        XCTAssertEqual(generator.calls.count, 1)
        XCTAssertEqual(generator.calls.last?.prompt, "a cup")
    }

    func test_generate_trimsPrompt_beforeDispatch() {
        let coordinator = makeCoordinator(initialPrompt: "   a cup  ")
        coordinator.generate()
        guard case .generating(let prompt) = coordinator.state else {
            XCTFail("Expected .generating"); return
        }
        XCTAssertEqual(prompt, "a cup")
        XCTAssertEqual(generator.calls.last?.prompt, "a cup")
    }

    func test_generate_withEmptyPrompt_doesNothing() {
        let coordinator = makeCoordinator(initialPrompt: nil)
        coordinator.generate()
        if case .generating = coordinator.state {
            XCTFail("Should not have entered .generating with empty prompt")
        }
        XCTAssertEqual(generator.calls.count, 0)
    }

    func test_generate_withWhitespacePrompt_doesNothing() {
        let coordinator = makeCoordinator(initialPrompt: "   \n\t  ")
        coordinator.generate()
        if case .generating = coordinator.state {
            XCTFail("Whitespace-only prompt should not generate")
        }
    }

    // MARK: - Result handling

    func test_successfulGeneration_transitionsToReviewing() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()

        let resultImage = solidImage(.blue)
        generator.deliver(.success(resultImage))

        guard case .reviewing(let image, let prompt) = coordinator.state else {
            XCTFail("Expected .reviewing"); return
        }
        XCTAssertEqual(image.size, resultImage.size)
        XCTAssertEqual(prompt, "a cup")
    }

    func test_failedGeneration_returnsToDescribing_withErrorMessage() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()

        generator.deliver(.failure(CartoonGenerationError.unavailableOnThisDevice))

        guard case .describing(let prompt, let errorMessage) = coordinator.state else {
            XCTFail("Expected .describing after failure"); return
        }
        XCTAssertEqual(prompt, "a cup", "Prompt preserved so user can retry")
        XCTAssertNotNil(errorMessage)
        XCTAssertTrue(errorMessage?.lowercased().contains("available") ?? false)
    }

    func test_staleResultIgnored_afterCancel() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()
        coordinator.cancelGeneration()

        // Generator fires anyway (stale callback). Coordinator should ignore it.
        generator.deliver(.success(solidImage(.green)))

        if case .reviewing = coordinator.state {
            XCTFail("Stale generator result must not affect post-cancel state")
        }
    }

    // MARK: - cancelGeneration

    func test_cancelGeneration_cancelsToken_andReturnsToDescribing() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()
        let token = generator.calls.last?.token
        XCTAssertNotNil(token)
        XCTAssertEqual(token?.isCancelled, false)

        coordinator.cancelGeneration()

        XCTAssertEqual(token?.isCancelled, true)
        guard case .describing(let prompt, _) = coordinator.state else {
            XCTFail("Expected back in .describing"); return
        }
        XCTAssertEqual(prompt, "a cup")
    }

    // MARK: - refine / confirm

    func test_refine_fromReviewing_returnsToDescribing_withPromptPreserved() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()
        generator.deliver(.success(solidImage(.blue)))

        coordinator.refine()

        guard case .describing(let prompt, let err) = coordinator.state else {
            XCTFail("Expected .describing"); return
        }
        XCTAssertEqual(prompt, "a cup")
        XCTAssertNil(err)
    }

    func test_confirm_fromReviewing_invokesOnSave_withResultAndPrompt() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()
        let resultImage = solidImage(.purple)
        generator.deliver(.success(resultImage))

        coordinator.confirm()

        XCTAssertEqual(savedResults.count, 1)
        XCTAssertEqual(savedResults.first?.0.size, resultImage.size)
        XCTAssertEqual(savedResults.first?.1, "a cup")
        XCTAssertEqual(cancelInvocations, 0)
    }

    // MARK: - cancel

    func test_cancel_invokesOnCancel_andCancelsActiveToken() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        coordinator.generate()
        let token = generator.calls.last?.token

        coordinator.cancel()

        XCTAssertEqual(token?.isCancelled, true)
        XCTAssertEqual(cancelInvocations, 1)
        XCTAssertEqual(savedResults.count, 0)
    }

    // MARK: - State observation

    func test_onStateChange_firesForEveryTransition() {
        let coordinator = makeCoordinator(initialPrompt: "a cup")
        var captured: [String] = []
        coordinator.onStateChange = { state in
            switch state {
            case .describing(_, let err):
                captured.append(err == nil ? "describing" : "describing(err)")
            case .generating: captured.append("generating")
            case .reviewing: captured.append("reviewing")
            }
        }

        coordinator.generate()
        generator.deliver(.success(solidImage(.cyan)))
        coordinator.refine()

        XCTAssertEqual(captured, ["generating", "reviewing", "describing"])
    }

    // MARK: - Helpers

    private func makeCoordinator(initialPrompt: String?) -> CartoonifyFlowCoordinator {
        CartoonifyFlowCoordinator(
            sourceImage: sourceImage,
            initialPrompt: initialPrompt,
            generator: generator,
            onSave: { [weak self] image, prompt in
                self?.savedResults.append((image, prompt))
            },
            onCancel: { [weak self] in
                self?.cancelInvocations += 1
            }
        )
    }

    private func solidImage(_ color: UIColor, size: CGSize = CGSize(width: 8, height: 8)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Spy generator

private final class SpyGenerator: CartoonGenerating {

    struct Call {
        let sourceImage: UIImage
        let prompt: String
        let completion: (Result<UIImage, Error>) -> Void
        let token: CartoonGenerationToken
    }

    private(set) var calls: [Call] = []

    @discardableResult
    func generate(
        sourceImage: UIImage,
        prompt: String,
        completion: @escaping (Result<UIImage, Error>) -> Void
    ) -> CartoonGenerationToken {
        let token = CartoonGenerationToken()
        calls.append(Call(
            sourceImage: sourceImage,
            prompt: prompt,
            completion: completion,
            token: token
        ))
        return token
    }

    func deliver(_ result: Result<UIImage, Error>) {
        calls.last?.completion(result)
    }
}
