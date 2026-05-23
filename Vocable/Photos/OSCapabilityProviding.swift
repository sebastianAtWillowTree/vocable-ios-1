//
//  OSCapabilityProviding.swift
//  Vocable
//
//  Test seam over OS version + device capability checks so the
//  experimental gate can be exercised without real Vision /
//  Image Playground hardware.
//

import Foundation

protocol OSCapabilityProviding {
    /// Whether Vision's foreground-subject extraction is supported.
    /// Requires iOS 17+.
    var isSubjectLiftAvailable: Bool { get }

    /// Whether Apple Image Playground stylization is supported.
    /// Requires iOS 18.1+ on an Apple-Intelligence-capable device.
    var isImagePlaygroundAvailable: Bool { get }

    /// Whether voice enhancement (isolation / denoise) is supported.
    /// Requires iOS 17+ for AVAudioEngine voice-processing input.
    var isVoiceEnhancementAvailable: Bool { get }
}

/// Real OS-backed implementation used in production.
struct SystemOSCapability: OSCapabilityProviding {

    var isSubjectLiftAvailable: Bool {
        if #available(iOS 17, *) {
            return true
        } else {
            return false
        }
    }

    var isImagePlaygroundAvailable: Bool {
        // Refined in Epic E (E3) to consult ImageCreator availability.
        // For now, gate purely by OS version; experimental toggle still
        // gates surfacing the feature.
        if #available(iOS 18.1, *) {
            return true
        } else {
            return false
        }
    }

    var isVoiceEnhancementAvailable: Bool {
        if #available(iOS 17, *) {
            return true
        } else {
            return false
        }
    }
}
