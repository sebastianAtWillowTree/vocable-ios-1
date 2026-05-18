//
//  SettingsExperimentalSectionViewModel.swift
//  Vocable
//
//  Settings logic for the "Experimental Features" row.
//  Kept separate from SettingsViewController so it can be tested
//  with stub capabilities and isolated UserDefaults.
//

import Foundation

final class SettingsExperimentalSectionViewModel {

    private let gate: ExperimentalFeatureGate

    init(gate: ExperimentalFeatureGate = ExperimentalFeatureGate()) {
        self.gate = gate
    }

    /// Whether the entire section should appear in the settings list.
    /// Hidden on devices where no experimental capability is supported.
    var isSectionVisible: Bool {
        gate.anyExperimentalAvailable
    }

    var rowTitle: String {
        String(
            localized: "settings.experimental_features.title",
            defaultValue: "Experimental Features"
        )
    }

    var rowValueDescription: String {
        if gate.isEnabled {
            return String(
                localized: "settings.experimental_features.state.on",
                defaultValue: "On"
            )
        } else {
            return String(
                localized: "settings.experimental_features.state.off",
                defaultValue: "Off"
            )
        }
    }

    /// Used as the accessibility label so VoiceOver announces both the
    /// row name and current toggle state in one read.
    var rowAccessibilityLabel: String {
        "\(rowTitle), \(rowValueDescription)"
    }

    var isToggleOn: Bool {
        gate.isEnabled
    }

    func toggle() {
        gate.isEnabled.toggle()
    }
}
