//
//  SettingsExperimentalSectionViewModelTests.swift
//  VocableTests
//

import XCTest
@testable import Vocable

final class SettingsExperimentalSectionViewModelTests: XCTestCase {

    private var suiteName: String!
    private var userDefaults: UserDefaults!

    override func setUpWithError() throws {
        try super.setUpWithError()
        suiteName = "SettingsExperimentalSectionViewModelTests.\(UUID().uuidString)"
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

    func test_isSectionVisible_isFalse_whenNoCapability() {
        let vm = makeViewModel(subjectLiftCapable: false, imagePlaygroundCapable: false)
        XCTAssertFalse(vm.isSectionVisible)
    }

    func test_isSectionVisible_isTrue_whenSubjectLiftCapable() {
        let vm = makeViewModel(subjectLiftCapable: true, imagePlaygroundCapable: false)
        XCTAssertTrue(vm.isSectionVisible)
    }

    func test_isSectionVisible_isTrue_whenImagePlaygroundCapable() {
        let vm = makeViewModel(subjectLiftCapable: false, imagePlaygroundCapable: true)
        XCTAssertTrue(vm.isSectionVisible)
    }

    func test_toggle_flipsGate() {
        let vm = makeViewModel(subjectLiftCapable: true, imagePlaygroundCapable: true)
        XCTAssertFalse(vm.isToggleOn)
        vm.toggle()
        XCTAssertTrue(vm.isToggleOn)
        vm.toggle()
        XCTAssertFalse(vm.isToggleOn)
    }

    func test_toggle_persistsAcrossInstances() {
        let first = makeViewModel(subjectLiftCapable: true, imagePlaygroundCapable: false)
        first.toggle()
        let second = makeViewModel(subjectLiftCapable: true, imagePlaygroundCapable: false)
        XCTAssertTrue(second.isToggleOn)
    }

    func test_rowAccessibilityLabel_includesOnState_whenEnabled() {
        let vm = makeViewModel(subjectLiftCapable: true, imagePlaygroundCapable: true)
        vm.toggle()
        XCTAssertTrue(vm.rowAccessibilityLabel.contains(vm.rowTitle))
        XCTAssertTrue(vm.rowAccessibilityLabel.contains(vm.rowValueDescription))
        XCTAssertEqual(vm.rowValueDescription, "On")
    }

    func test_rowAccessibilityLabel_includesOffState_whenDisabled() {
        let vm = makeViewModel(subjectLiftCapable: true, imagePlaygroundCapable: true)
        XCTAssertTrue(vm.rowAccessibilityLabel.contains(vm.rowTitle))
        XCTAssertEqual(vm.rowValueDescription, "Off")
    }

    // MARK: - Helpers

    private func makeViewModel(
        subjectLiftCapable: Bool,
        imagePlaygroundCapable: Bool
    ) -> SettingsExperimentalSectionViewModel {
        let capability = StubOSCapability(
            isSubjectLiftAvailable: subjectLiftCapable,
            isImagePlaygroundAvailable: imagePlaygroundCapable
        )
        let gate = ExperimentalFeatureGate(capability: capability, userDefaults: userDefaults)
        return SettingsExperimentalSectionViewModel(gate: gate)
    }
}

private struct StubOSCapability: OSCapabilityProviding {
    let isSubjectLiftAvailable: Bool
    let isImagePlaygroundAvailable: Bool
}
