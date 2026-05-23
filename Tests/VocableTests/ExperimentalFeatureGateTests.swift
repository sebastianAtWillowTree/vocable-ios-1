//
//  ExperimentalFeatureGateTests.swift
//  VocableTests
//

import XCTest
@testable import Vocable

final class ExperimentalFeatureGateTests: XCTestCase {

    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "ExperimentalFeatureGateTests.\(UUID().uuidString)"
        userDefaults = UserDefaults(suiteName: suiteName)
        userDefaults.removePersistentDomain(forName: suiteName)
    }

    override func tearDownWithError() throws {
        userDefaults.removePersistentDomain(forName: suiteName)
        userDefaults = nil
        suiteName = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_gate_subjectLift_returnsFalse_whenToggleOff() {
        let gate = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: true)
        gate.isEnabled = false
        XCTAssertFalse(gate.isSubjectLiftAvailable)
    }

    func test_gate_subjectLift_returnsTrue_whenToggleOnAndOSAtLeast17() {
        let gate = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: false)
        gate.isEnabled = true
        XCTAssertTrue(gate.isSubjectLiftAvailable)
    }

    func test_gate_subjectLift_returnsFalse_whenToggleOnButOSBelow17() {
        let gate = makeGate(subjectLiftCapable: false, imagePlaygroundCapable: false)
        gate.isEnabled = true
        XCTAssertFalse(gate.isSubjectLiftAvailable)
    }

    func test_gate_imagePlayground_returnsFalse_whenDeviceNotAICapable() {
        let gate = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: false)
        gate.isEnabled = true
        XCTAssertFalse(gate.isImagePlaygroundAvailable)
    }

    func test_gate_imagePlayground_returnsTrue_whenToggleOnAndCapable() {
        let gate = makeGate(subjectLiftCapable: false, imagePlaygroundCapable: true)
        gate.isEnabled = true
        XCTAssertTrue(gate.isImagePlaygroundAvailable)
    }

    func test_gate_anyExperimentalAvailable_isTrue_ifSubjectLiftCapable() {
        let gate = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: false)
        XCTAssertTrue(gate.anyExperimentalAvailable)
    }

    func test_gate_anyExperimentalAvailable_isTrue_ifImagePlaygroundCapable() {
        let gate = makeGate(subjectLiftCapable: false, imagePlaygroundCapable: true)
        XCTAssertTrue(gate.anyExperimentalAvailable)
    }

    func test_gate_anyExperimentalAvailable_isFalse_ifNeitherCapable() {
        let gate = makeGate(subjectLiftCapable: false, imagePlaygroundCapable: false)
        XCTAssertFalse(gate.anyExperimentalAvailable)
    }

    func test_anyExperimentalAvailable_doesNotRequireToggleOn() {
        // Even with toggle off, capability presence alone should surface
        // the section so the caregiver has a way to turn it on.
        let gate = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: false)
        gate.isEnabled = false
        XCTAssertTrue(gate.anyExperimentalAvailable)
    }

    func test_togglingExperimentalMode_persistsAcrossLaunches() {
        let first = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: false)
        first.isEnabled = true

        // Simulate a "new launch" by constructing a fresh gate with the
        // same UserDefaults backing store.
        let second = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: false)
        XCTAssertTrue(second.isEnabled)
    }

    func test_isEnabled_defaultsToFalse() {
        let gate = makeGate(subjectLiftCapable: true, imagePlaygroundCapable: true)
        XCTAssertFalse(gate.isEnabled)
    }

    func test_gate_voiceEnhancement_returnsFalse_whenToggleOff() {
        let gate = makeGate(subjectLiftCapable: false, imagePlaygroundCapable: false, voiceEnhancementCapable: true)
        gate.isEnabled = false
        XCTAssertFalse(gate.isVoiceEnhancementAvailable)
    }

    func test_gate_voiceEnhancement_returnsTrue_whenToggleOnAndCapable() {
        let gate = makeGate(subjectLiftCapable: false, imagePlaygroundCapable: false, voiceEnhancementCapable: true)
        gate.isEnabled = true
        XCTAssertTrue(gate.isVoiceEnhancementAvailable)
    }

    func test_gate_anyExperimentalAvailable_isTrue_ifVoiceEnhancementCapable() {
        let gate = makeGate(subjectLiftCapable: false, imagePlaygroundCapable: false, voiceEnhancementCapable: true)
        XCTAssertTrue(gate.anyExperimentalAvailable)
    }

    // MARK: - Helpers

    private func makeGate(
        subjectLiftCapable: Bool,
        imagePlaygroundCapable: Bool,
        voiceEnhancementCapable: Bool = false
    ) -> ExperimentalFeatureGate {
        let capability = StubOSCapability(
            isSubjectLiftAvailable: subjectLiftCapable,
            isImagePlaygroundAvailable: imagePlaygroundCapable,
            isVoiceEnhancementAvailable: voiceEnhancementCapable
        )
        return ExperimentalFeatureGate(capability: capability, userDefaults: userDefaults)
    }
}

private struct StubOSCapability: OSCapabilityProviding {
    let isSubjectLiftAvailable: Bool
    let isImagePlaygroundAvailable: Bool
    let isVoiceEnhancementAvailable: Bool
}
