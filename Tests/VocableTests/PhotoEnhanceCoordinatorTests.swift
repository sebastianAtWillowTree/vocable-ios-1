//
//  PhotoEnhanceCoordinatorTests.swift
//  VocableTests
//
//  Covers E1 (variant picker branching) and E4 (progress UI invoked
//  + cancel propagation). E2/E3 production code is tested indirectly:
//  the coordinator routes to the right service, and the service
//  itself is OS-gated in production.
//

import XCTest
import UIKit
@testable import Vocable

final class PhotoEnhanceCoordinatorTests: XCTestCase {

    private var host: UIViewController!
    private var picker: SpyVariantPicker!
    private var lifter: SpySubjectLifter!
    private var cartoonifier: SpyCartoonifier!
    private var preflight: SpyPreflightPresenter!
    private var progress: SpyProgress!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        host = UIViewController()
        picker = SpyVariantPicker()
        lifter = SpySubjectLifter()
        cartoonifier = SpyCartoonifier()
        preflight = SpyPreflightPresenter()
        progress = SpyProgress()
        suiteName = "PhotoEnhanceCoordinatorTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - E1: bypass / branching

    func test_enhance_bypasses_whenExperimentalDisabled() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: true, toggleOn: false)
        let input = makeImage(color: .red)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, from: host) { outcome in
            received = .some(outcome)
        }
        XCTAssertEqual(picker.presentCount, 0)
        XCTAssertEqual(received.flatMap { $0 }?.image.size, input.size)
        XCTAssertNil(received.flatMap { $0 }?.cartoonPrompt)
    }

    func test_enhance_bypasses_whenNoVariantAvailable() {
        let coordinator = makeCoordinator(subjectLift: false, cartoonify: false, toggleOn: true)
        let input = makeImage(color: .red)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        XCTAssertEqual(picker.presentCount, 0)
        XCTAssertEqual(received.flatMap { $0 }?.image.size, input.size)
    }

    func test_enhance_presentsPicker_whenSubjectLiftAvailable() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: false, toggleOn: true)
        coordinator.enhance(image: makeImage(color: .red), from: host) { _ in }
        XCTAssertEqual(picker.presentCount, 1)
        XCTAssertEqual(picker.lastVariants, [.original, .subjectLift])
    }

    func test_enhance_presentsPicker_includingBothVariants_whenAvailable() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: true, toggleOn: true)
        coordinator.enhance(image: makeImage(color: .red), from: host) { _ in }
        XCTAssertEqual(picker.lastVariants, [.original, .subjectLift, .cartoonify])
    }

    func test_cartoonify_notOffered_whenApplierIsNil() {
        // Mirrors category-authoring construction: no cartoonifyApplier
        // passed in. The variant must not appear in the picker even if
        // the gate's iOS-version check is positive.
        let capability = StubCapability(
            isSubjectLiftAvailable: false,
            isImagePlaygroundAvailable: true,
            isVoiceEnhancementAvailable: false
        )
        let gate = ExperimentalFeatureGate(capability: capability, userDefaults: userDefaults)
        gate.isEnabled = true
        let coordinator = PhotoEnhanceCoordinator(
            gate: gate,
            picker: picker,
            subjectLifter: lifter,
            cartoonifyApplier: nil,
            progress: progress
        )
        coordinator.enhance(image: makeImage(color: .red), from: host) { _ in }
        XCTAssertEqual(picker.presentCount, 0,
                       "Without a cartoonifyApplier and no other variants, the picker is bypassed")
    }

    func test_selectingOriginal_returnsInputUnchanged() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: false, toggleOn: true)
        let input = makeImage(color: .green)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.original)
        XCTAssertEqual(received.flatMap { $0 }?.image.size, input.size)
        XCTAssertNil(received.flatMap { $0 }?.cartoonPrompt)
        XCTAssertEqual(lifter.calls.count, 0)
    }

    func test_selectingSubjectLift_invokesService() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: false, toggleOn: true)
        let input = makeImage(color: .green)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.subjectLift)
        XCTAssertEqual(lifter.calls.count, 1)
        XCTAssertNil(received)

        let lifted = makeImage(color: .blue)
        lifter.deliver(lifted)
        XCTAssertEqual(received.flatMap { $0 }?.image.size, lifted.size)
        XCTAssertNil(received.flatMap { $0 }?.cartoonPrompt)
    }

    func test_subjectLiftReturnsNil_fallsBackToOriginal() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: false, toggleOn: true)
        let input = makeImage(color: .green)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.subjectLift)
        lifter.deliver(nil)
        XCTAssertEqual(received.flatMap { $0 }?.image.size, input.size)
    }

    // MARK: - CC15: pipeline order — preflight → applier → post-lift

    func test_selectingCartoonify_invokesApplier_withInitialPrompt() {
        // With subjectLift available, .cartoonify hands the ORIGINAL image
        // to the applier and lifts the cartoonified RESULT afterwards.
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: true, toggleOn: true)
        let input = makeImage(color: .green, size: CGSize(width: 32, height: 32))
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, initialCartoonPrompt: "a red ball", from: host) {
            received = .some($0)
        }
        picker.lastOnSelect?(.cartoonify)

        // Applier kicks off first on the ORIGINAL — no pre-lift, no preflight.
        XCTAssertEqual(lifter.calls.count, 0)
        XCTAssertEqual(cartoonifier.calls.count, 1)
        XCTAssertEqual(cartoonifier.calls.last?.sourceImage.size, input.size)
        XCTAssertEqual(cartoonifier.calls.last?.initialPrompt, "a red ball")
        XCTAssertNil(received)

        let cartoonImage = makeImage(color: .magenta, size: CGSize(width: 64, height: 64))
        cartoonifier.deliver(CartoonifyOutcome(image: cartoonImage, prompt: "a red ball"))

        // Post-lift runs on the CARTOON output.
        XCTAssertEqual(lifter.calls.count, 1)
        XCTAssertEqual(lifter.calls.last?.0.size, cartoonImage.size)
        XCTAssertNil(received)

        let liftedCartoon = makeImage(color: .yellow, size: CGSize(width: 48, height: 48))
        lifter.deliver(liftedCartoon)

        XCTAssertEqual(received.flatMap { $0 }?.image.size, liftedCartoon.size)
        XCTAssertEqual(received.flatMap { $0 }?.cartoonPrompt, "a red ball")
    }

    func test_selectingCartoonify_whenPostLiftReturnsNil_keepsCartoonAsIs() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: true, toggleOn: true)
        let input = makeImage(color: .green)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.cartoonify)

        let cartoonImage = makeImage(color: .magenta, size: CGSize(width: 64, height: 64))
        cartoonifier.deliver(CartoonifyOutcome(image: cartoonImage, prompt: ""))

        XCTAssertEqual(lifter.calls.count, 1)
        lifter.deliver(nil)

        // Lift returned nil — outcome image stays the cartoon (no failure).
        XCTAssertEqual(received.flatMap { $0 }?.image.size, cartoonImage.size)
    }

    func test_selectingCartoonify_withoutSubjectLiftAvailable_skipsPostLift() {
        // Edge: gate.isSubjectLiftAvailable == false (older iOS). Cartoonify
        // still works because post-lift is opportunistic; the cartoon output
        // is the final image.
        let coordinator = makeCoordinator(subjectLift: false, cartoonify: true, toggleOn: true)
        let input = makeImage(color: .green)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.cartoonify)

        XCTAssertEqual(cartoonifier.calls.count, 1)
        XCTAssertEqual(cartoonifier.calls.last?.sourceImage.size, input.size)

        let cartoonImage = makeImage(color: .magenta, size: CGSize(width: 64, height: 64))
        cartoonifier.deliver(CartoonifyOutcome(image: cartoonImage, prompt: "x"))

        XCTAssertEqual(lifter.calls.count, 0, "Post-lift skipped when gate marks lift unavailable")
        XCTAssertEqual(received.flatMap { $0 }?.image.size, cartoonImage.size)
        XCTAssertEqual(received.flatMap { $0 }?.cartoonPrompt, "x")
    }

    func test_cartoonifyCancelled_returnsNilOutcome_andSkipsPostLift() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: true, toggleOn: true)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: makeImage(color: .green), from: host) {
            received = .some($0)
        }
        picker.lastOnSelect?(.cartoonify)
        cartoonifier.deliver(nil)
        XCTAssertEqual(lifter.calls.count, 0, "Post-lift must not run when applier was cancelled")
        XCTAssertNotNil(received)
        XCTAssertNil(received.flatMap { $0 })
    }

    // MARK: - CC13/CC15: preflight comes BEFORE applier, post-lift comes AFTER

    func test_cartoonifyWithPreflight_runsPreflight_thenApplier_thenPostLift() {
        let coordinator = makeCoordinator(
            subjectLift: true,
            cartoonify: true,
            toggleOn: true,
            withPreflight: true
        )
        let input = makeImage(color: .green, size: CGSize(width: 32, height: 32))
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: input, initialCartoonPrompt: "a red ball", from: host) {
            received = .some($0)
        }
        picker.lastOnSelect?(.cartoonify)

        // Preflight first, on the ORIGINAL image. No lift yet, no applier.
        XCTAssertEqual(preflight.calls.count, 1)
        XCTAssertEqual(preflight.calls.last?.sourceImage.size, input.size)
        XCTAssertEqual(preflight.calls.last?.initialPrompt, "a red ball")
        XCTAssertEqual(cartoonifier.calls.count, 0)
        XCTAssertEqual(lifter.calls.count, 0)

        // Caregiver confirmed a slightly different prompt — that should reach
        // the applier.
        preflight.deliver(.init(confirmedPrompt: "a bright red ball"))

        XCTAssertEqual(cartoonifier.calls.count, 1)
        XCTAssertEqual(cartoonifier.calls.last?.sourceImage.size, input.size,
                       "Applier receives the ORIGINAL (preflight does not lift)")
        XCTAssertEqual(cartoonifier.calls.last?.initialPrompt, "a bright red ball")
        XCTAssertEqual(lifter.calls.count, 0)

        let cartoonImage = makeImage(color: .magenta, size: CGSize(width: 64, height: 64))
        cartoonifier.deliver(CartoonifyOutcome(image: cartoonImage, prompt: "a bright red ball"))

        // Post-lift on the cartoon.
        XCTAssertEqual(lifter.calls.count, 1)
        XCTAssertEqual(lifter.calls.last?.0.size, cartoonImage.size)
        XCTAssertNil(received)

        let liftedCartoon = makeImage(color: .yellow, size: CGSize(width: 48, height: 48))
        lifter.deliver(liftedCartoon)
        XCTAssertEqual(received.flatMap { $0 }?.image.size, liftedCartoon.size)
        XCTAssertEqual(received.flatMap { $0 }?.cartoonPrompt, "a bright red ball")
    }

    func test_cartoonifyWithPreflight_cancelledAtPreflight_returnsNilOutcome_andSkipsApplier() {
        let coordinator = makeCoordinator(
            subjectLift: true,
            cartoonify: true,
            toggleOn: true,
            withPreflight: true
        )
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: makeImage(color: .green), from: host) { received = .some($0) }
        picker.lastOnSelect?(.cartoonify)
        XCTAssertEqual(preflight.calls.count, 1)

        preflight.deliver(nil) // cancelled

        XCTAssertEqual(cartoonifier.calls.count, 0, "Applier must not run when preflight was cancelled")
        XCTAssertEqual(lifter.calls.count, 0)
        XCTAssertNotNil(received)
        XCTAssertNil(received.flatMap { $0 })
    }

    func test_cartoonifyWithoutPreflight_skipsPreflight_andHandsDirectlyToApplier() {
        // Regression for legacy/test configurations that omit the preflight.
        let coordinator = makeCoordinator(
            subjectLift: true,
            cartoonify: true,
            toggleOn: true,
            withPreflight: false
        )
        coordinator.enhance(image: makeImage(color: .green), initialCartoonPrompt: "x", from: host) { _ in }
        picker.lastOnSelect?(.cartoonify)

        XCTAssertEqual(preflight.calls.count, 0)
        XCTAssertEqual(cartoonifier.calls.count, 1)
        XCTAssertEqual(cartoonifier.calls.last?.initialPrompt, "x")
    }

    func test_cartoonify_progressShown_duringPostLift_dismissedBeforeCompletion() {
        // Progress UI wraps the POST-lift now (Image Playground has its own modal).
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: true, toggleOn: true)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: makeImage(color: .green), from: host) { received = .some($0) }
        picker.lastOnSelect?(.cartoonify)

        // No progress while the applier is doing its own thing.
        XCTAssertEqual(progress.showCount, 0)

        let cartoonImage = makeImage(color: .magenta, size: CGSize(width: 64, height: 64))
        cartoonifier.deliver(CartoonifyOutcome(image: cartoonImage, prompt: ""))

        // Now the post-lift step is running with progress UI.
        XCTAssertEqual(progress.showCount, 1)
        XCTAssertEqual(progress.dismissCount, 0)
        XCTAssertNil(received)

        lifter.deliver(makeImage(color: .yellow))
        XCTAssertEqual(progress.dismissCount, 1)
        XCTAssertNotNil(received)
    }

    func test_cancel_returnsNilCompletion() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: true, toggleOn: true)
        var received: PhotoEnhanceOutcome??
        coordinator.enhance(image: makeImage(color: .green), from: host) { received = .some($0) }
        picker.lastOnCancel?()
        XCTAssertNotNil(received)
        XCTAssertNil(received.flatMap { $0 })
    }

    // MARK: - E4: progress invoked + dismissed

    func test_subjectLift_invokesProgressShow_andDismissesOnCompletion() {
        let coordinator = makeCoordinator(subjectLift: true, cartoonify: false, toggleOn: true)
        coordinator.enhance(image: makeImage(color: .red), from: host) { _ in }
        picker.lastOnSelect?(.subjectLift)

        XCTAssertEqual(progress.showCount, 1, "Progress UI should be requested before service starts")
        XCTAssertEqual(progress.dismissCount, 0)

        lifter.deliver(makeImage(color: .blue))
        XCTAssertEqual(progress.dismissCount, 1, "Progress UI should be dismissed when service finishes")
    }

    // MARK: - Helpers

    private func makeCoordinator(
        subjectLift: Bool,
        cartoonify: Bool,
        toggleOn: Bool,
        withPreflight: Bool = false
    ) -> PhotoEnhanceCoordinator {
        let capability = StubCapability(
            isSubjectLiftAvailable: subjectLift,
            isImagePlaygroundAvailable: cartoonify,
            isVoiceEnhancementAvailable: false
        )
        let gate = ExperimentalFeatureGate(capability: capability, userDefaults: userDefaults)
        if toggleOn { gate.isEnabled = true }
        return PhotoEnhanceCoordinator(
            gate: gate,
            picker: picker,
            subjectLifter: lifter,
            cartoonifyApplier: cartoonify ? cartoonifier : nil,
            preflightPresenter: (cartoonify && withPreflight) ? preflight : nil,
            progress: progress
        )
    }

    private func makeImage(color: UIColor, size: CGSize = CGSize(width: 16, height: 16)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Test doubles

private struct StubCapability: OSCapabilityProviding {
    let isSubjectLiftAvailable: Bool
    let isImagePlaygroundAvailable: Bool
    let isVoiceEnhancementAvailable: Bool
}

private final class SpyVariantPicker: PhotoEnhanceVariantPickerPresenting {
    private(set) var presentCount = 0
    private(set) var lastVariants: [PhotoEnhanceVariant] = []
    var lastOnSelect: ((PhotoEnhanceVariant) -> Void)?
    var lastOnCancel: (() -> Void)?

    func presentVariantPicker(
        from presenter: UIViewController,
        original: UIImage,
        availableVariants: [PhotoEnhanceVariant],
        onSelect: @escaping (PhotoEnhanceVariant) -> Void,
        onCancel: @escaping () -> Void
    ) {
        presentCount += 1
        lastVariants = availableVariants
        lastOnSelect = onSelect
        lastOnCancel = onCancel
    }
}

private final class SpySubjectLifter: SubjectLiftPerforming {
    private(set) var calls: [(UIImage, (UIImage?) -> Void)] = []

    func performSubjectLift(
        on image: UIImage,
        completion: @escaping (UIImage?) -> Void
    ) {
        calls.append((image, completion))
    }

    func deliver(_ image: UIImage?) {
        calls.last?.1(image)
    }
}

private final class SpyCartoonifier: CartoonifyApplying {

    struct Call {
        let sourceImage: UIImage
        let initialPrompt: String?
        let completion: (CartoonifyOutcome?) -> Void
    }

    private(set) var calls: [Call] = []

    func performCartoonify(
        on image: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyOutcome?) -> Void
    ) {
        calls.append(Call(sourceImage: image, initialPrompt: initialPrompt, completion: completion))
    }

    func deliver(_ outcome: CartoonifyOutcome?) {
        calls.last?.completion(outcome)
    }
}

private final class SpyPreflightPresenter: CartoonifyPreflightPresenting {

    struct Call {
        let sourceImage: UIImage
        let initialPrompt: String?
        let completion: (CartoonifyPreflightOutcome?) -> Void
    }

    private(set) var calls: [Call] = []

    func presentPreflight(
        sourceImage: UIImage,
        initialPrompt: String?,
        from presenter: UIViewController,
        completion: @escaping (CartoonifyPreflightOutcome?) -> Void
    ) {
        calls.append(Call(
            sourceImage: sourceImage,
            initialPrompt: initialPrompt,
            completion: completion
        ))
    }

    func deliver(_ outcome: CartoonifyPreflightOutcome?) {
        calls.last?.completion(outcome)
    }
}

private final class SpyProgress: EnhancementProgressDisplaying {
    private(set) var showCount = 0
    private(set) var dismissCount = 0

    func show(
        from presenter: UIViewController,
        delay: TimeInterval,
        onCancel: @escaping () -> Void
    ) -> () -> Void {
        showCount += 1
        return { [weak self] in self?.dismissCount += 1 }
    }
}

extension PhotoEnhanceVariant: Equatable {}
