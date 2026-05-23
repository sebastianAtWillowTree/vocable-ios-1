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
    private var stylizer: SpyStylizer!
    private var progress: SpyProgress!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        host = UIViewController()
        picker = SpyVariantPicker()
        lifter = SpySubjectLifter()
        stylizer = SpyStylizer()
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
        let coordinator = makeCoordinator(subjectLift: true, stylize: true, toggleOn: false)
        let input = makeImage(color: .red)
        var received: UIImage??
        coordinator.enhance(image: input, from: host) { image in
            received = .some(image)
        }
        XCTAssertEqual(picker.presentCount, 0)
        XCTAssertEqual(received.flatMap { $0 }?.size, input.size)
    }

    func test_enhance_bypasses_whenNoVariantAvailable() {
        let coordinator = makeCoordinator(subjectLift: false, stylize: false, toggleOn: true)
        let input = makeImage(color: .red)
        var received: UIImage??
        coordinator.enhance(image: input, from: host) { image in
            received = .some(image)
        }
        XCTAssertEqual(picker.presentCount, 0)
        XCTAssertEqual(received.flatMap { $0 }?.size, input.size)
    }

    func test_enhance_presentsPicker_whenSubjectLiftAvailable() {
        let coordinator = makeCoordinator(subjectLift: true, stylize: false, toggleOn: true)
        coordinator.enhance(image: makeImage(color: .red), from: host) { _ in }
        XCTAssertEqual(picker.presentCount, 1)
        XCTAssertEqual(picker.lastVariants, [.original, .subjectLift])
    }

    func test_enhance_presentsPicker_includingBothVariants_whenAvailable() {
        let coordinator = makeCoordinator(subjectLift: true, stylize: true, toggleOn: true)
        coordinator.enhance(image: makeImage(color: .red), from: host) { _ in }
        XCTAssertEqual(picker.lastVariants, [.original, .subjectLift, .stylize])
    }

    func test_selectingOriginal_returnsInputUnchanged() {
        let coordinator = makeCoordinator(subjectLift: true, stylize: false, toggleOn: true)
        let input = makeImage(color: .green)
        var received: UIImage??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.original)
        XCTAssertEqual(received.flatMap { $0 }?.size, input.size)
        XCTAssertEqual(lifter.calls.count, 0)
    }

    func test_selectingSubjectLift_invokesService() {
        let coordinator = makeCoordinator(subjectLift: true, stylize: false, toggleOn: true)
        let input = makeImage(color: .green)
        var received: UIImage??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.subjectLift)
        XCTAssertEqual(lifter.calls.count, 1)
        XCTAssertNil(received)

        let lifted = makeImage(color: .blue)
        lifter.deliver(lifted)
        XCTAssertEqual(received.flatMap { $0 }?.size, lifted.size)
    }

    func test_subjectLiftReturnsNil_fallsBackToOriginal() {
        let coordinator = makeCoordinator(subjectLift: true, stylize: false, toggleOn: true)
        let input = makeImage(color: .green)
        var received: UIImage??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.subjectLift)
        lifter.deliver(nil)
        XCTAssertEqual(received.flatMap { $0 }?.size, input.size)
    }

    func test_selectingStylize_invokesService() {
        let coordinator = makeCoordinator(subjectLift: false, stylize: true, toggleOn: true)
        let input = makeImage(color: .green)
        var received: UIImage??
        coordinator.enhance(image: input, from: host) { received = .some($0) }
        picker.lastOnSelect?(.stylize)
        XCTAssertEqual(stylizer.calls.count, 1)
        stylizer.deliver(nil)    // Production placeholder may not implement
        XCTAssertEqual(received.flatMap { $0 }?.size, input.size)
    }

    func test_cancel_returnsNilCompletion() {
        let coordinator = makeCoordinator(subjectLift: true, stylize: true, toggleOn: true)
        var received: UIImage??
        coordinator.enhance(image: makeImage(color: .green), from: host) { received = .some($0) }
        picker.lastOnCancel?()
        XCTAssertNotNil(received)
        XCTAssertNil(received.flatMap { $0 })
    }

    // MARK: - E4: progress invoked + dismissed

    func test_subjectLift_invokesProgressShow_andDismissesOnCompletion() {
        let coordinator = makeCoordinator(subjectLift: true, stylize: false, toggleOn: true)
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
        stylize: Bool,
        toggleOn: Bool
    ) -> PhotoEnhanceCoordinator {
        let capability = StubCapability(
            isSubjectLiftAvailable: subjectLift,
            isImagePlaygroundAvailable: stylize,
            isVoiceEnhancementAvailable: false
        )
        let gate = ExperimentalFeatureGate(capability: capability, userDefaults: userDefaults)
        if toggleOn { gate.isEnabled = true }
        return PhotoEnhanceCoordinator(
            gate: gate,
            picker: picker,
            subjectLifter: lifter,
            stylizer: stylizer,
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

private final class SpyStylizer: ImagePlaygroundStylizing {
    private(set) var calls: [(UIImage, (UIImage?) -> Void)] = []

    func performStylize(
        on image: UIImage,
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        calls.append((image, completion))
    }

    func deliver(_ image: UIImage?) {
        calls.last?.1(image)
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
