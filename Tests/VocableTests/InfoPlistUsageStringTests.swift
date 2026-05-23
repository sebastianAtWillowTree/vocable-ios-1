//
//  InfoPlistUsageStringTests.swift
//  VocableTests
//
//  Lint-style tests that ensure the camera and photo-library usage
//  description strings exist and resolve through the localization
//  machinery rather than leaking the "Localized in Supporting Files"
//  placeholder text at runtime.
//

import XCTest

final class InfoPlistUsageStringTests: XCTestCase {

    private let placeholderMarker = "Localized in Supporting Files"

    func test_infoPlist_containsNSCameraUsageDescription() throws {
        let value = try unwrappedInfoString(forKey: "NSCameraUsageDescription")
        XCTAssertFalse(value.isEmpty)
        XCTAssertFalse(value.contains(placeholderMarker),
                       "NSCameraUsageDescription should resolve to a localized string, not the placeholder")
    }

    func test_infoPlist_containsNSPhotoLibraryUsageDescription() throws {
        let value = try unwrappedInfoString(forKey: "NSPhotoLibraryUsageDescription")
        XCTAssertFalse(value.isEmpty)
        XCTAssertFalse(value.contains(placeholderMarker),
                       "NSPhotoLibraryUsageDescription should resolve to a localized string, not the placeholder")
    }

    func test_NSCameraUsageDescription_explainsPhotoCaptureUse() throws {
        let value = try unwrappedInfoString(forKey: "NSCameraUsageDescription")
        // App Store guidance: each permission string should explain ALL uses
        // of the underlying capability. We extended camera to cover both head
        // tracking and photo capture; assert the photo-capture use is named.
        XCTAssertTrue(
            value.lowercased().contains("photo") || value.lowercased().contains("card"),
            "Camera usage description should mention photo capture for AAC cards"
        )
    }

    func test_NSMicrophoneUsageDescription_explainsVoiceRecordingUse() throws {
        let value = try unwrappedInfoString(forKey: "NSMicrophoneUsageDescription")
        // The original purpose (listening mode) and the new purpose (voice
        // recording for cards) must both be covered per App Store guidance.
        let lower = value.lowercased()
        XCTAssertTrue(
            lower.contains("listening") || lower.contains("transcrib"),
            "Microphone usage description should still cover listening mode"
        )
        XCTAssertTrue(
            lower.contains("record") || lower.contains("voice") || lower.contains("cadence"),
            "Microphone usage description should mention voice recording for cards"
        )
    }

    // MARK: - Helpers

    private func unwrappedInfoString(forKey key: String) throws -> String {
        // Resolve via the Vocable app bundle (the test host).
        let bundle = try locateAppBundle()
        let value = bundle.object(forInfoDictionaryKey: key) as? String
        return try XCTUnwrap(value, "Info.plist key \(key) was missing or non-string")
    }

    private func locateAppBundle() throws -> Bundle {
        // The app bundle is the test host on iOS, so Bundle.main resolves
        // to Vocable.app. Fall back to walking bundles by identifier.
        if Bundle.main.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil {
            return Bundle.main
        }
        for bundle in Bundle.allBundles where bundle.object(forInfoDictionaryKey: "NSCameraUsageDescription") != nil {
            return bundle
        }
        XCTFail("Could not locate Vocable app bundle from tests")
        throw NSError(domain: "InfoPlistUsageStringTests", code: -1)
    }
}
