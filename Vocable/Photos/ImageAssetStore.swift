//
//  ImageAssetStore.swift
//  Vocable
//
//  File-backed image store. Caregiver-supplied photos are persisted
//  in Application Support/PhraseImages/<uuid>.{jpg|png}.
//
//  Format selection: images that actually contain transparent pixels
//  (subject-lifted / cartoonified subjects) are written as PNG so the
//  alpha survives; everything else is JPEG to keep files small. The
//  asset ID is just the UUID — the on-disk extension is an internal
//  detail resolved by load/delete.
//

import UIKit

enum ImageAssetStoreError: Error {
    case encodingFailed
}

struct ImageAssetStore: ImageAssetStoring {

    /// Extensions this store recognizes, in resolution-priority order.
    private static let supportedExtensions = ["png", "jpg"]

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
        let id = UUID().uuidString
        let data: Data
        let pathExtension: String
        if Self.containsTransparency(image) {
            guard let png = image.pngData() else {
                throw ImageAssetStoreError.encodingFailed
            }
            data = png
            pathExtension = "png"
        } else {
            guard let jpeg = image.jpegData(compressionQuality: compressionQuality) else {
                throw ImageAssetStoreError.encodingFailed
            }
            data = jpeg
            pathExtension = "jpg"
        }
        try data.write(to: fileURL(for: id, pathExtension: pathExtension), options: .atomic)
        return id
    }

    func load(id: String) -> UIImage? {
        guard let url = existingFileURL(for: id),
              let data = try? Data(contentsOf: url)
        else {
            return nil
        }
        return UIImage(data: data)
    }

    func delete(id: String) throws {
        guard let url = existingFileURL(for: id) else { return }
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
            guard Self.supportedExtensions.contains(url.pathExtension) else { return nil }
            return url.deletingPathExtension().lastPathComponent
        }
    }

    // MARK: - Helpers

    private func fileURL(for id: String, pathExtension: String) -> URL {
        baseDirectory.appendingPathComponent("\(id).\(pathExtension)")
    }

    /// Resolves the on-disk URL for an ID, checking each supported
    /// extension. Returns nil if no file exists.
    private func existingFileURL(for id: String) -> URL? {
        for ext in Self.supportedExtensions {
            let url = baseDirectory.appendingPathComponent("\(id).\(ext)")
            if fileManager.fileExists(atPath: url.path) { return url }
        }
        return nil
    }

    /// True when the image actually contains translucent pixels (not
    /// merely an alpha channel — UIGraphicsImageRenderer output usually
    /// carries an alpha channel even when fully opaque). Samples a
    /// reduced-resolution copy so the cost is independent of source
    /// size; transparent regions survive downscaling.
    static func containsTransparency(_ image: UIImage) -> Bool {
        guard let cgImage = image.cgImage else { return false }
        switch cgImage.alphaInfo {
        case .none, .noneSkipFirst, .noneSkipLast:
            // No alpha channel at all — definitely opaque.
            return false
        default:
            break
        }

        let sampleSide = 24
        var pixels = [UInt8](repeating: 0, count: sampleSide * sampleSide * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixels,
            width: sampleSide,
            height: sampleSide,
            bitsPerComponent: 8,
            bytesPerRow: sampleSide * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return false
        }
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: sampleSide, height: sampleSide))

        // Any meaningfully-transparent pixel ⇒ treat the image as
        // transparent and persist as PNG.
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] < 250 {
            return true
        }
        return false
    }
}
