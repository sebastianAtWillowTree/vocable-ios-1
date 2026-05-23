//
//  AudioPlaybackServiceTests.swift
//  VocableTests
//
//  Contract-level coverage for the playback service. Real AVAudioPlayer
//  interaction is exercised indirectly by AudioAssetStoreTests +
//  manual QA; here we cover the protocol shape and stop() being safe
//  to call on an idle player.
//

import XCTest
@testable import Vocable

final class AudioPlaybackServiceTests: XCTestCase {

    func test_isPlaying_isFalse_beforeAnyPlayCall() {
        let service = AudioPlaybackService()
        XCTAssertFalse(service.isPlaying)
    }

    func test_stop_isSafe_whenNothingIsPlaying() {
        let service = AudioPlaybackService()
        XCTAssertNoThrow(service.stop())
        XCTAssertFalse(service.isPlaying)
    }

    func test_play_unknownFile_throws() {
        let service = AudioPlaybackService()
        let badURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("does-not-exist-\(UUID().uuidString).m4a")
        XCTAssertThrowsError(try service.play(url: badURL))
    }

    /// The fake-driven tests in higher layers (VC2 wiring) verify that
    /// callers can substitute their own AudioPlaybackServicing — this
    /// test pins the protocol's existence so renames can't silently
    /// break that contract.
    func test_protocol_isInhabitedBy_AudioPlaybackService() {
        let service: AudioPlaybackServicing = AudioPlaybackService()
        XCTAssertFalse(service.isPlaying)
    }
}
