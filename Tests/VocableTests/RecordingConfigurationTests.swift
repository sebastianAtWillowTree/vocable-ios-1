//
//  RecordingConfigurationTests.swift
//  VocableTests
//
//  AudioCaptureService can't be unit-tested against AVAudioSession on
//  CI, so the contract-level coverage focuses on the encoder
//  configuration that determines on-disk format and quality.
//

import XCTest
import AVFoundation
@testable import Vocable

final class RecordingConfigurationTests: XCTestCase {

    func test_defaultM4A_isMPEG4AAC_monoAt22050Hz_64kbps() {
        let config = RecordingConfiguration.defaultM4A
        XCTAssertEqual(config.formatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(config.sampleRate, 22050)
        XCTAssertEqual(config.channels, 1)
        XCTAssertEqual(config.bitRate, 64_000)
        XCTAssertEqual(config.quality, .medium)
    }

    func test_avAudioRecorderSettings_includesAllRequiredKeys() {
        let settings = RecordingConfiguration.defaultM4A.avAudioRecorderSettings

        XCTAssertEqual(settings[AVFormatIDKey] as? AudioFormatID, kAudioFormatMPEG4AAC)
        XCTAssertEqual(settings[AVSampleRateKey] as? Double, 22050)
        XCTAssertEqual(settings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(settings[AVEncoderBitRateKey] as? Int, 64_000)
        XCTAssertEqual(settings[AVEncoderAudioQualityKey] as? Int, AVAudioQuality.medium.rawValue)
    }

    func test_canConstruct_avAudioRecorder_withDefaultSettings() throws {
        // Verifies AVAudioRecorder accepts the settings dictionary on
        // this OS — catches any future SDK change that rejects the
        // production configuration before it ships.
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("RecordingConfigurationTests-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertNoThrow(
            try AVAudioRecorder(url: url, settings: RecordingConfiguration.defaultM4A.avAudioRecorderSettings)
        )
    }
}
