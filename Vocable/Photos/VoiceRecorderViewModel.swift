//
//  VoiceRecorderViewModel.swift
//  Vocable
//
//  State machine for the voice recorder. The view controller drives
//  this via user input and observes `state` for rendering. Auto-stops
//  at maxDuration so the caregiver can't accidentally produce a
//  10-minute card.
//

import Foundation

final class VoiceRecorderViewModel {

    enum State: Equatable {
        case ready
        case recording(elapsed: TimeInterval)
        case review(audioData: Data)
    }

    /// Callback fired whenever `state` changes.
    var onStateChange: ((State) -> Void)?

    let maxDuration: TimeInterval
    private(set) var state: State = .ready {
        didSet { onStateChange?(state) }
    }

    private let captureService: AudioCaptureServicing

    init(
        captureService: AudioCaptureServicing,
        maxDuration: TimeInterval = 15
    ) {
        self.captureService = captureService
        self.maxDuration = maxDuration
    }

    // MARK: - Actions

    func startRecording() throws {
        guard case .ready = state else { return }
        _ = try captureService.prepare()
        try captureService.start()
        state = .recording(elapsed: 0)
    }

    func stopRecording() throws {
        guard case .recording = state else { return }
        let data = try captureService.stop()
        state = .review(audioData: data)
    }

    /// Drops the captured recording and returns to `.ready`.
    func discardAndReturnToReady() {
        captureService.cancel()
        state = .ready
    }

    /// Returns the recorded audio if currently in review state.
    func confirmedData() -> Data? {
        if case let .review(data) = state { return data }
        return nil
    }

    /// Called by the recording timer at regular intervals while recording.
    /// Advances elapsed time and auto-stops if maxDuration is reached.
    func tick(_ interval: TimeInterval) throws {
        guard case let .recording(elapsed) = state else { return }
        let newElapsed = elapsed + interval
        if newElapsed >= maxDuration {
            try stopRecording()
        } else {
            state = .recording(elapsed: newElapsed)
        }
    }
}
