//
//  AudioAssetStore.swift
//  Vocable
//
//  File-backed audio store. Caregiver-supplied recordings are persisted
//  as .m4a in Application Support/Recordings/<uuid>.m4a.
//

import Foundation

struct AudioAssetStore: AudioAssetStoring {

    /// Default on-device location used by the app.
    static let defaultDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Recordings", isDirectory: true)
    }()

    /// File extension used on disk. Matches the encoding produced by
    /// AudioCaptureService (AAC inside MPEG-4 container).
    static let fileExtension = "m4a"

    let baseDirectory: URL
    private let fileManager: FileManager

    init(
        baseDirectory: URL = AudioAssetStore.defaultDirectory,
        fileManager: FileManager = .default
    ) throws {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
    }

    func save(_ data: Data) throws -> String {
        let id = UUID().uuidString
        try data.write(to: fileURL(for: id), options: .atomic)
        return id
    }

    func load(id: String) -> Data? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try? Data(contentsOf: url)
    }

    func url(for id: String) -> URL? {
        let url = fileURL(for: id)
        return fileManager.fileExists(atPath: url.path) ? url : nil
    }

    func delete(id: String) throws {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path) else { return }
        try fileManager.removeItem(at: url)
    }

    func deleteAll() throws {
        for id in allAssetIDs() {
            try delete(id: id)
        }
    }

    func allAssetIDs() -> [String] {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: baseDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return []
        }
        return contents.compactMap { url -> String? in
            guard url.pathExtension == Self.fileExtension else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
    }

    private func fileURL(for id: String) -> URL {
        baseDirectory.appendingPathComponent("\(id).\(Self.fileExtension)")
    }
}
