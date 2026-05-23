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

final class AudioPlaybackService: AudioPlaybackServicing {

    private var player: AVAudioPlayer?

    var isPlaying: Bool { player?.isPlaying ?? false }

    func play(url: URL) throws {
        player?.stop()

        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [])
        try session.setActive(true, options: [])

        let next = try AVAudioPlayer(contentsOf: url)
        next.prepareToPlay()
        next.play()
        player = next
    }

    func stop() {
        player?.stop()
        player = nil
    }
}
