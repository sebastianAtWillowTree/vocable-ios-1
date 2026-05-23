//
//  AudioEnhanceCoordinatorTests.swift
//  VocableTests
//
//  Covers VE1 (variant picker branching) and VE3 (progress + cancel).
//  VE2 production is gated by iOS 17+ — the coordinator routes to it
//  through a protocol seam so this test exercises the contract.
//

import XCTest
import UIKit
@testable import Vocable

final class AudioEnhanceCoordinatorTests: XCTestCase {

    private var host: UIViewController!
    private var picker: SpyPicker!
    private var isolator: SpyIsolator!
    private var progress: SpyProgress!
    private var userDefaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        try super.setUpWithError()
        host = UIViewController()
        picker = SpyPicker()
        isolator = SpyIsolator()
        progress = SpyProgress()
        suiteName = "AudioEnhanceCoordinatorTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        try super.tearDownWithError()
    }

    // MARK: - VE1: bypass / branching

    func test_enhance_bypasses_whenExperimentalDisabled() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: true, toggleOn: false)
        var received: Data??
        coordinator.enhance(audioData: Data([0x01]), from: host) { received = .some($0) }
        XCTAssertEqual(picker.presentCount, 0)
        XCTAssertEqual(received.flatMap { $0 }, Data([0x01]))
    }

    func test_enhance_bypasses_whenNotCapable() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: false, toggleOn: true)
        var received: Data??
        coordinator.enhance(audioData: Data([0x02]), from: host) { received = .some($0) }
        XCTAssertEqual(picker.presentCount, 0)
        XCTAssertEqual(received.flatMap { $0 }, Data([0x02]))
    }

    func test_enhance_presentsPicker_whenCapable() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: true, toggleOn: true)
        coordinator.enhance(audioData: Data([0x03]), from: host) { _ in }
        XCTAssertEqual(picker.presentCount, 1)
        XCTAssertEqual(picker.lastVariants, [.original, .voiceIsolation])
    }

    func test_selectingOriginal_returnsInput() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: true, toggleOn: true)
        var received: Data??
        coordinator.enhance(audioData: Data([0x04]), from: host) { received = .some($0) }
        picker.lastOnSelect?(.original)
        XCTAssertEqual(received.flatMap { $0 }, Data([0x04]))
        XCTAssertEqual(isolator.calls.count, 0)
    }

    func test_selectingVoiceIsolation_invokesService() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: true, toggleOn: true)
        var received: Data??
        coordinator.enhance(audioData: Data([0x05]), from: host) { received = .some($0) }
        picker.lastOnSelect?(.voiceIsolation)
        XCTAssertEqual(isolator.calls.count, 1)
        XCTAssertNil(received)

        isolator.deliver(Data([0x99]))
        XCTAssertEqual(received.flatMap { $0 }, Data([0x99]))
    }

    func test_isolationReturnsNil_fallsBackToOriginal() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: true, toggleOn: true)
        var received: Data??
        coordinator.enhance(audioData: Data([0x06]), from: host) { received = .some($0) }
        picker.lastOnSelect?(.voiceIsolation)
        isolator.deliver(nil)
        XCTAssertEqual(received.flatMap { $0 }, Data([0x06]))
    }

    func test_cancel_returnsNilCompletion() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: true, toggleOn: true)
        var received: Data??
        coordinator.enhance(audioData: Data([0x07]), from: host) { received = .some($0) }
        picker.lastOnCancel?()
        XCTAssertNotNil(received)
        XCTAssertNil(received.flatMap { $0 })
    }

    // MARK: - VE3: progress UI

    func test_voiceIsolation_invokesProgressShow_andDismissesOnCompletion() {
        let coordinator = makeCoordinator(voiceEnhancementCapable: true, toggleOn: true)
        coordinator.enhance(audioData: Data([0x08]), from: host) { _ in }
        picker.lastOnSelect?(.voiceIsolation)

        XCTAssertEqual(progress.showCount, 1)
        XCTAssertEqual(progress.dismissCount, 0)

        isolator.deliver(Data([0x99]))
        XCTAssertEqual(progress.dismissCount, 1)
    }

    // MARK: - Helpers

    private func makeCoordinator(
        voiceEnhancementCapable: Bool,
        toggleOn: Bool
    ) -> AudioEnhanceCoordinator {
        let capability = StubCapability(
            isSubjectLiftAvailable: false,
            isImagePlaygroundAvailable: false,
            isVoiceEnhancementAvailable: voiceEnhancementCapable
        )
        let gate = ExperimentalFeatureGate(capability: capability, userDefaults: userDefaults)
        if toggleOn { gate.isEnabled = true }
        return AudioEnhanceCoordinator(
            gate: gate,
            picker: picker,
            isolator: isolator,
            progress: progress
        )
    }
}

// MARK: - Test doubles

private struct StubCapability: OSCapabilityProviding {
    let isSubjectLiftAvailable: Bool
    let isImagePlaygroundAvailable: Bool
    let isVoiceEnhancementAvailable: Bool
}

private final class SpyPicker: AudioEnhanceVariantPickerPresenting {
    private(set) var presentCount = 0
    private(set) var lastVariants: [AudioEnhanceVariant] = []
    var lastOnSelect: ((AudioEnhanceVariant) -> Void)?
    var lastOnCancel: (() -> Void)?

    func presentVariantPicker(
        from presenter: UIViewController,
        availableVariants: [AudioEnhanceVariant],
        onSelect: @escaping (AudioEnhanceVariant) -> Void,
        onCancel: @escaping () -> Void
    ) {
        presentCount += 1
        lastVariants = availableVariants
        lastOnSelect = onSelect
        lastOnCancel = onCancel
    }
}

private final class SpyIsolator: VoiceIsolationPerforming {
    private(set) var calls: [(Data, (Data?) -> Void)] = []

    func performVoiceIsolation(
        on audioData: Data,
        completion: @escaping (Data?) -> Void
    ) {
        calls.append((audioData, completion))
    }

    func deliver(_ data: Data?) {
        calls.last?.1(data)
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

extension AudioEnhanceVariant: Equatable {}
