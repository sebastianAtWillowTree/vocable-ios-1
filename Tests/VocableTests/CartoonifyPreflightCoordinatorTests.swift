//
//  CartoonifyPreflightCoordinatorTests.swift
//  VocableTests
//
//  Drives the preflight state machine: enteringPrompt → classifying →
//  aligned (callback) | misaligned (alert). Aligner is stubbed; no
//  UIKit, no Vision.
//

import XCTest
import UIKit
@testable import Vocable

final class CartoonifyPreflightCoordinatorTests: XCTestCase {

    private var aligner: StubAligner!
    private var sourceImage: UIImage!
    private var continueCalls: [String] = []
    private var cancelCalls: Int = 0
    private var stateChanges: [CartoonifyPreflightCoordinator.State] = []

    override func setUp() {
        super.setUp()
        aligner = StubAligner()
        sourceImage = UIImage()
        continueCalls = []
        cancelCalls = 0
        stateChanges = []
    }

    // MARK: - Initial state

    func test_initialState_isEnteringPrompt_withSeededPrompt() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        guard case .enteringPrompt(let prompt) = coordinator.state else {
            return XCTFail("Expected .enteringPrompt, got \(coordinator.state)")
        }
        XCTAssertEqual(prompt, "a red ball")
    }

    func test_initialState_normalizesNilPromptToEmptyString() {
        let coordinator = makeCoordinator(initialPrompt: nil)
        guard case .enteringPrompt(let prompt) = coordinator.state else {
            return XCTFail("Expected .enteringPrompt, got \(coordinator.state)")
        }
        XCTAssertEqual(prompt, "")
    }

    // MARK: - Update prompt

    func test_updatePrompt_replacesPromptInEnteringPromptState() {
        let coordinator = makeCoordinator(initialPrompt: "old")
        coordinator.updatePrompt("new")
        if case .enteringPrompt(let prompt) = coordinator.state {
            XCTAssertEqual(prompt, "new")
        } else {
            XCTFail("Expected .enteringPrompt, got \(coordinator.state)")
        }
    }

    func test_updatePrompt_ignoredInOtherStates() {
        // While classifying, prompt edits are dropped — there's no UI for them.
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.continueFromPrompt()
        if case .classifying = coordinator.state { /* ok */ } else {
            XCTFail("Expected .classifying after continueFromPrompt, got \(coordinator.state)")
        }
        coordinator.updatePrompt("changed mid-flight")
        if case .classifying(let p) = coordinator.state {
            XCTAssertEqual(p, "a red ball", "Prompt should not change during classifying")
        } else {
            XCTFail("Expected .classifying, got \(coordinator.state)")
        }
    }

    // MARK: - Continue from prompt

    func test_continueFromPrompt_trimsWhitespace_andRefusesEmpty() {
        let coordinator = makeCoordinator(initialPrompt: "   ")
        coordinator.continueFromPrompt()
        // Refused — still in enteringPrompt; aligner not invoked.
        if case .enteringPrompt(let prompt) = coordinator.state {
            XCTAssertEqual(prompt, "   ")
        } else {
            XCTFail("Expected to stay in .enteringPrompt, got \(coordinator.state)")
        }
        XCTAssertEqual(aligner.calls.count, 0)
        XCTAssertEqual(continueCalls.count, 0)
    }

    func test_continueFromPrompt_transitionsToClassifying_andInvokesAligner() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.continueFromPrompt()
        if case .classifying(let p) = coordinator.state {
            XCTAssertEqual(p, "a red ball")
        } else {
            XCTFail("Expected .classifying, got \(coordinator.state)")
        }
        XCTAssertEqual(aligner.calls.count, 1)
        XCTAssertEqual(aligner.calls.last?.prompt, "a red ball")
    }

    // MARK: - Aligner results

    func test_alignerAligned_invokesOnContinue_withTrimmedPrompt() {
        let coordinator = makeCoordinator(initialPrompt: "  a red ball  ")
        coordinator.continueFromPrompt()
        aligner.deliver(.aligned)
        XCTAssertEqual(continueCalls, ["a red ball"])
        XCTAssertEqual(cancelCalls, 0)
    }

    func test_alignerUnknownInsufficientSignal_proceedsSilently() {
        // No misalignment alert — proceed as if aligned.
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.continueFromPrompt()
        aligner.deliver(.unknownInsufficientSignal)
        XCTAssertEqual(continueCalls, ["a red ball"])
    }

    func test_alignerMisaligned_transitionsToMisalignedState() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.continueFromPrompt()
        let reason: AlignmentMismatchReason = .noOverlapBetweenPromptAndImage(
            promptNouns: ["ball"],
            imageLabelHeadNouns: ["computer"]
        )
        aligner.deliver(.misaligned(reason: reason))

        if case .misaligned(let prompt, let r) = coordinator.state {
            XCTAssertEqual(prompt, "a red ball")
            XCTAssertEqual(r, reason)
        } else {
            XCTFail("Expected .misaligned, got \(coordinator.state)")
        }
        XCTAssertEqual(continueCalls.count, 0)
    }

    // MARK: - From .misaligned

    func test_continueAnywayFromMisaligned_invokesOnContinue() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.continueFromPrompt()
        aligner.deliver(.misaligned(reason: .noOverlapBetweenPromptAndImage(
            promptNouns: ["ball"],
            imageLabelHeadNouns: ["computer"]
        )))
        coordinator.continueAnyway()
        XCTAssertEqual(continueCalls, ["a red ball"])
    }

    func test_editDescriptionFromMisaligned_returnsToEnteringPrompt() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.continueFromPrompt()
        aligner.deliver(.misaligned(reason: .personSubjectButPromptIsObject(promptNouns: ["ball"])))

        coordinator.editDescription()
        if case .enteringPrompt(let p) = coordinator.state {
            XCTAssertEqual(p, "a red ball")
        } else {
            XCTFail("Expected .enteringPrompt, got \(coordinator.state)")
        }
        XCTAssertEqual(continueCalls.count, 0)
    }

    // MARK: - Cancellation

    func test_cancel_invokesOnCancel_fromAnyState() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.cancel()
        XCTAssertEqual(cancelCalls, 1)
    }

    func test_cancel_duringClassifying_dropsLateAlignerResult() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        coordinator.continueFromPrompt()
        coordinator.cancel()
        XCTAssertEqual(cancelCalls, 1)

        // Late .aligned arrives — must not fire onContinue.
        aligner.deliver(.aligned)
        XCTAssertEqual(continueCalls.count, 0)
    }

    // MARK: - State-change callback

    func test_stateChange_callback_firesForEveryTransition() {
        let coordinator = makeCoordinator(initialPrompt: "a red ball")
        // initial state-change after attaching
        coordinator.continueFromPrompt() // → .classifying
        aligner.deliver(.misaligned(reason: .personSubjectButPromptIsObject(promptNouns: ["ball"])))
        // → .misaligned
        coordinator.editDescription()
        // → .enteringPrompt
        XCTAssertEqual(stateChanges.count, 3)
        if case .classifying = stateChanges[0] { /* ok */ } else { XCTFail("[0] not .classifying") }
        if case .misaligned = stateChanges[1] { /* ok */ } else { XCTFail("[1] not .misaligned") }
        if case .enteringPrompt = stateChanges[2] { /* ok */ } else { XCTFail("[2] not .enteringPrompt") }
    }

    // MARK: - Helpers

    private func makeCoordinator(initialPrompt: String?) -> CartoonifyPreflightCoordinator {
        let coordinator = CartoonifyPreflightCoordinator(
            sourceImage: sourceImage,
            initialPrompt: initialPrompt,
            aligner: aligner,
            onContinue: { [weak self] prompt in
                self?.continueCalls.append(prompt)
            },
            onCancel: { [weak self] in
                self?.cancelCalls += 1
            }
        )
        coordinator.onStateChange = { [weak self] state in
            self?.stateChanges.append(state)
        }
        return coordinator
    }
}

// MARK: - Test doubles

private final class StubAligner: PromptSubjectAligning {

    struct Call {
        let image: UIImage
        let prompt: String
        let completion: (AlignmentResult) -> Void
    }

    private(set) var calls: [Call] = []

    func align(
        image: UIImage,
        prompt: String,
        completion: @escaping (AlignmentResult) -> Void
    ) {
        calls.append(Call(image: image, prompt: prompt, completion: completion))
    }

    func deliver(_ result: AlignmentResult) {
        calls.last?.completion(result)
    }
}
