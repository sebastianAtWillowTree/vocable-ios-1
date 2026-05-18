//
//  ImageAssetStore.swift
//  Vocable
//
//  File-backed JPEG store. Caregiver-supplied photos are persisted
//  in Application Support/PhraseImages/<uuid>.jpg.
//

import UIKit

enum ImageAssetStoreError: Error {
    case encodingFailed
}

struct ImageAssetStore: ImageAssetStoring {

    /// Default on-device location used by the app.
    static let defaultDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("PhraseImages", isDirectory: true)
    }()

    let baseDirectory: URL
    private let fileManager: FileManager
    private let compressionQuality: CGFloat

    init(
        baseDirectory: URL = ImageAssetStore.defaultDirectory,
        fileManager: FileManager = .default,
        compressionQuality: CGFloat = 0.85
    ) throws {
        self.baseDirectory = baseDirectory
        self.fileManager = fileManager
        self.compressionQuality = compressionQuality
        try fileManager.createDirectory(
            at: baseDirectory,
            withIntermediateDirectories: true
        )
    }

    func save(_ image: UIImage) throws -> String {
        guard let data = image.jpegData(compressionQuality: compressionQuality) else {
            throw ImageAssetStoreError.encodingFailed
        }
        let id = UUID().uuidString
        try data.write(to: fileURL(for: id), options: .atomic)
        return id
    }

    func load(id: String) -> UIImage? {
        let url = fileURL(for: id)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return UIImage(data: data)
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
            guard url.pathExtension == "jpg" else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
    }

    private func fileURL(for id: String) -> URL {
        baseDirectory.appendingPathComponent("\(id).jpg")
    }
}
