//
//  AudioPlaybackService.swift
//  Vocable
//
//  Plays back a previously-recorded phrase. Owns a single
//  AVAudioPlayer so a new play() stops any prior playback —
//  caregivers tapping cards rapidly shouldn't stack audio.
//

import Foundation
import AVFoundation

protocol AudioPlaybackServicing: AnyObject {
    var isPlaying: Bool { get }
    func play(url: URL) throws
    func stop()
}

final class AudioPlaybackService: NSObject, AudioPlaybackServicing, AVAudioPlayerDelegate {

    private var player: AVAudioPlayer?

    /// Held for the duration of playback so AudioEngineController
    /// suspends its engine. Released on stop / natural completion /
    /// decode error (ARC idempotent across paths).
    private var audioLease: AudioExclusiveLease?

    override init() {
        super.init()
    }

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(url: URL) throws {
        player?.stop()

        // Acquire before any session work so the engine controller
        // suspends before our category change lands.
        audioLease = AudioExclusiveCoordinator.shared.acquire(reason: "Audio playback")

        let session = AVAudioSession.sharedInstance()
        // Match AudioEngineController's playback category/mode so the
        // listening-mode path doesn't have to re-fight the session
        // after we play a recording.
        try session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
        try session.setActive(true, options: [])

        let next = try AVAudioPlayer(contentsOf: url)
        next.delegate = self
        next.prepareToPlay()
        next.play()
        player = next
    }

    func stop() {
        player?.stop()
        player = nil
        deactivateSession()
    }

    // MARK: - AVAudioPlayerDelegate

    func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        // Release the audio session so other audio (music, TTS,
        // listening mode) can resume immediately.
        self.player = nil
        deactivateSession()
    }

    func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        self.player = nil
        deactivateSession()
    }

    // MARK: - Helpers

    private func deactivateSession() {
        try? AVAudioSession.sharedInstance().setActive(
            false,
            options: .notifyOthersOnDeactivation
        )
        // Release the lease AFTER deactivating so the engine controller
        // doesn't try to reactivate the session while we're still
        // tearing down.
        audioLease = nil
    }
}
