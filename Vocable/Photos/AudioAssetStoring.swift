//
//  AudioAssetStoring.swift
//  Vocable
//
//  Protocol seam for audio asset persistence. Audio is fronted by
//  raw Data + a URL accessor so AVAudioPlayer can stream from disk
//  without loading the whole recording into memory.
//

import Foundation

protocol AudioAssetStoring {
    func save(_ data: Data) throws -> String
    func load(id: String) -> Data?
    func url(for id: String) -> URL?
    func delete(id: String) throws
    func deleteAll() throws
    func allAssetIDs() -> [String]
}
