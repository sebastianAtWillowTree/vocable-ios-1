//
//  AudioCaptureService.swift
//  Vocable
//
//  Captures a phrase recording. AVAudioRecorder underneath in
//  production; the protocol seam lets the recording UI and the
//  enhancement pipeline run against fakes in tests.
//

import Foundation
import AVFoundation

protocol AudioCaptureServicing: AnyObject {
    /// Current input level, expressed as power in dBFS (-160…0).
    /// -160 is silence; 0 is clipping. Useful for a live meter.
    var currentInputLevelDB: Float { get }

    /// True while recording is active.
    var isRecording: Bool { get }

    /// Prepare the recorder. Must be called once before start().
    /// Returns the URL the recording will be written to.
    func prepare() throws -> URL

    /// Begin recording. Sets isRecording = true.
    func start() throws

    /// Stop recording and return the recorded `.m4a` data.
    /// After this call isRecording = false. The on-disk file is
    /// deleted; the caller is expected to persist via AudioAssetStore.
    func stop() throws -> Data

    /// Abort the recording without producing data and discard the file.
    func cancel()
}

/// Encoder settings used by the production capture service. Pulled out
/// as a value so tests can assert the contract without running real audio.
struct RecordingConfiguration {
    let formatID: AudioFormatID
    let sampleRate: Double
    let channels: Int
    let bitRate: Int
    let quality: AVAudioQuality

    static let defaultM4A = RecordingConfiguration(
        formatID: kAudioFormatMPEG4AAC,
        sampleRate: 22050,
        channels: 1,
        bitRate: 64_000,
        quality: .medium
    )

    var avAudioRecorderSettings: [String: Any] {
        [
            AVFormatIDKey: formatID,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVEncoderBitRateKey: bitRate,
            AVEncoderAudioQualityKey: quality.rawValue
        ]
    }
}

enum AudioCaptureError: Error {
    case notPrepared
    case missingOutputData
}

/// Production implementation backed by AVAudioRecorder.
/// Not unit-tested directly; relies on AVAudioSession which only
/// behaves correctly on a device or with a configured simulator audio
/// session. The contract is exercised through AudioCaptureServicing
/// fakes at higher layers.
final class AudioCaptureService: AudioCaptureServicing {

    private let configuration: RecordingConfiguration
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    init(
        configuration: RecordingConfiguration = .defaultM4A,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
    }

    var currentInputLevelDB: Float {
        guard let recorder, recorder.isRecording else { return -160 }
        recorder.updateMeters()
        return recorder.averagePower(forChannel: 0)
    }

    var isRecording: Bool {
        recorder?.isRecording ?? false
    }

    func prepare() throws -> URL {
        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("AudioCapture")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).m4a")

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
        try session.setActive(true, options: [])

        let recorder = try AVAudioRecorder(url: url, settings: configuration.avAudioRecorderSettings)
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        self.recorder = recorder
        self.outputURL = url
        return url
    }

    func start() throws {
        guard let recorder else { throw AudioCaptureError.notPrepared }
        recorder.record()
    }

    func stop() throws -> Data {
        guard let recorder, let outputURL else {
            throw AudioCaptureError.notPrepared
        }
        recorder.stop()
        defer { discardOutputFile() }

        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else { throw AudioCaptureError.missingOutputData }
        return data
    }

    func cancel() {
        recorder?.stop()
        discardOutputFile()
    }

    private func discardOutputFile() {
        if let outputURL {
            try? fileManager.removeItem(at: outputURL)
        }
        recorder = nil
        outputURL = nil
    }
}
