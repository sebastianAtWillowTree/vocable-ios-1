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
///
/// Audio-session settings (.playAndRecord, .spokenAudio,
/// [.defaultToSpeaker]) match the existing AudioEngineController
/// so the two systems don't fight each other when listening mode
/// and recording overlap. Every setActive(true) is paired with a
/// setActive(false, options: .notifyOthersOnDeactivation) on
/// stop/cancel so other audio resumes when we're done.
///
/// Adopts AVAudioRecorderDelegate to surface encode errors that
/// would otherwise be silent. The file is finalized by the time
/// stop() returns (Apple guarantee), but the delegate lets us log
/// or react to failures.
final class AudioCaptureService: NSObject, AudioCaptureServicing, AVAudioRecorderDelegate {

    private let configuration: RecordingConfiguration
    private let fileManager: FileManager
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?
    private var encodeError: Error?

    init(
        configuration: RecordingConfiguration = .defaultM4A,
        fileManager: FileManager = .default
    ) {
        self.configuration = configuration
        self.fileManager = fileManager
        super.init()
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
        // Defensive: a previous prepare() without stop()/cancel() left
        // an orphan temp file behind. Clear it before we overwrite.
        discardOutputFile()

        let directory = fileManager.temporaryDirectory
            .appendingPathComponent("AudioCapture")
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("\(UUID().uuidString).m4a")

        let session = AVAudioSession.sharedInstance()
        // Match AudioEngineController's category/mode so we don't fight
        // listening-mode setup if the user oscillates between features.
        try session.setCategory(.playAndRecord, mode: .spokenAudio, options: [.defaultToSpeaker])
        try session.setActive(true, options: [])

        let recorder = try AVAudioRecorder(url: url, settings: configuration.avAudioRecorderSettings)
        recorder.delegate = self
        recorder.isMeteringEnabled = true
        recorder.prepareToRecord()

        self.recorder = recorder
        self.outputURL = url
        self.encodeError = nil
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
        defer {
            deactivateSession()
            discardOutputFile()
        }

        if let encodeError {
            throw encodeError
        }
        let data = try Data(contentsOf: outputURL)
        guard !data.isEmpty else { throw AudioCaptureError.missingOutputData }
        return data
    }

    func cancel() {
        recorder?.stop()
        deactivateSession()
        discardOutputFile()
    }

    // MARK: - AVAudioRecorderDelegate

    func audioRecorderDidFinishRecording(
        _ recorder: AVAudioRecorder,
        successfully flag: Bool
    ) {
        if !flag {
            encodeError = AudioCaptureError.missingOutputData
        }
    }

    func audioRecorderEncodeErrorDidOccur(
        _ recorder: AVAudioRecorder,
        error: Error?
    ) {
        encodeError = error ?? AudioCaptureError.missingOutputData
    }

    // MARK: - Helpers

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
    }

    private func discardOutputFile() {
        if let outputURL {
            try? fileManager.removeItem(at: outputURL)
        }
        recorder = nil
        outputURL = nil
    }
}
