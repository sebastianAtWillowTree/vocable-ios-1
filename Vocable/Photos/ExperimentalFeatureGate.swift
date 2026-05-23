//
//  ExperimentalFeatureGate.swift
//  Vocable
//
//  Combines the caregiver-facing experimental toggle with the
//  runtime OS/device capability check. The toggle is persisted in
//  UserDefaults; the capability check is delegated to OSCapabilityProviding.
//

import Foundation

struct ExperimentalFeatureGate {

    static let toggleDefaultsKey = "ExperimentalFeatureGate.enabled"

    private let capability: OSCapabilityProviding
    private let userDefaults: UserDefaults

    init(
        capability: OSCapabilityProviding = SystemOSCapability(),
        userDefaults: UserDefaults = .standard
    ) {
        self.capability = capability
        self.userDefaults = userDefaults
    }

    /// Caregiver-controlled toggle. Off by default. Persisted.
    var isEnabled: Bool {
        get { userDefaults.bool(forKey: Self.toggleDefaultsKey) }
        nonmutating set { userDefaults.set(newValue, forKey: Self.toggleDefaultsKey) }
    }

    /// True iff the toggle is on AND the device supports subject lift.
    var isSubjectLiftAvailable: Bool {
        isEnabled && capability.isSubjectLiftAvailable
    }

    /// True iff the toggle is on AND the device supports Image Playground.
    var isImagePlaygroundAvailable: Bool {
        isEnabled && capability.isImagePlaygroundAvailable
    }

    /// True iff the toggle is on AND the device supports voice enhancement.
    var isVoiceEnhancementAvailable: Bool {
        isEnabled && capability.isVoiceEnhancementAvailable
    }

    /// True iff *any* experimental capability is supported by the device,
    /// regardless of toggle state. Used to decide whether the Experimental
    /// Features settings section should be visible at all.
    var anyExperimentalAvailable: Bool {
        capability.isSubjectLiftAvailable
            || capability.isImagePlaygroundAvailable
            || capability.isVoiceEnhancementAvailable
    }
}
