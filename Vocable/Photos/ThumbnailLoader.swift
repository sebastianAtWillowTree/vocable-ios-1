//
//  ThumbnailLoader.swift
//  Vocable
//
//  Loads downscaled thumbnails from the image asset store. Caches
//  results in memory (NSCache evicts under memory pressure). Decoding
//  happens off the main queue so list scrolling stays smooth.
//

import UIKit

protocol ThumbnailLoading {
    @discardableResult
    func loadThumbnail(
        id: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> ThumbnailLoadToken
}

final class ThumbnailLoadToken {
    fileprivate var isCancelled = false
    func cancel() { isCancelled = true }
}

final class ThumbnailLoader: ThumbnailLoading {

    private let store: ImageAssetStoring
    private let processingQueue: DispatchQueue
    private let cache: NSCache<NSString, UIImage>

    init(
        store: ImageAssetStoring,
        processingQueue: DispatchQueue = DispatchQueue(
            label: "ThumbnailLoader.processing",
            qos: .userInitiated
        )
    ) {
        self.store = store
        self.processingQueue = processingQueue
        self.cache = NSCache<NSString, UIImage>()
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleMemoryWarning),
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @discardableResult
    func loadThumbnail(
        id: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> ThumbnailLoadToken {
        let token = ThumbnailLoadToken()
        let cacheKey = Self.cacheKey(id: id, targetSize: targetSize)

        if let cached = cache.object(forKey: cacheKey) {
            DispatchQueue.main.async {
                if token.isCancelled { return }
                completion(cached)
            }
            return token
        }

        processingQueue.async { [weak self] in
            guard let self else { return }
            if token.isCancelled { return }

            guard let image = self.store.load(id: id),
                  let downscaled = Self.downscale(image, to: targetSize)
            else {
                DispatchQueue.main.async {
                    if token.isCancelled { return }
                    completion(nil)
                }
                return
            }

            self.cache.setObject(downscaled, forKey: cacheKey)
            DispatchQueue.main.async {
                if token.isCancelled { return }
                completion(downscaled)
            }
        }

        return token
    }

    @objc private func handleMemoryWarning() {
        cache.removeAllObjects()
    }

    // MARK: - Helpers

    private static func cacheKey(id: String, targetSize: CGSize) -> NSString {
        "\(id)|\(Int(targetSize.width))x\(Int(targetSize.height))" as NSString
    }

    private static func downscale(_ image: UIImage, to targetSize: CGSize) -> UIImage? {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
