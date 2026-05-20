//
//  ThumbnailLoaderTests.swift
//  VocableTests
//

import XCTest
import UIKit
@testable import Vocable

final class ThumbnailLoaderTests: XCTestCase {

    private var store: SpyImageAssetStore!
    private var loader: ThumbnailLoader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = SpyImageAssetStore()
        loader = ThumbnailLoader(store: store)
    }

    override func tearDownWithError() throws {
        loader = nil
        store = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_loadThumbnail_invokesStoreLoad_andReturnsDownscaledImage() {
        store.stubbedImage = makeImage(size: CGSize(width: 400, height: 400))
        let expectation = expectation(description: "thumbnail delivered")

        var received: UIImage?
        _ = loader.loadThumbnail(
            id: "abc",
            targetSize: CGSize(width: 64, height: 64)
        ) { image in
            received = image
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        XCTAssertEqual(store.loadCalls, ["abc"])
        XCTAssertEqual(received?.size, CGSize(width: 64, height: 64))
    }

    func test_loadThumbnail_unknownID_returnsNil() {
        store.stubbedImage = nil
        let expectation = expectation(description: "completion delivered")

        var received: UIImage? = makeImage(size: CGSize(width: 1, height: 1))
        _ = loader.loadThumbnail(
            id: "missing",
            targetSize: CGSize(width: 32, height: 32)
        ) { image in
            received = image
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 2)
        XCTAssertNil(received)
    }

    func test_loadThumbnail_secondCall_returnsCachedImage_withoutStoreLoad() {
        store.stubbedImage = makeImage(size: CGSize(width: 200, height: 200))

        let firstExpectation = expectation(description: "first load")
        _ = loader.loadThumbnail(id: "cache-me", targetSize: CGSize(width: 32, height: 32)) { _ in
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 2)
        XCTAssertEqual(store.loadCalls.count, 1)

        let secondExpectation = expectation(description: "second load")
        var receivedFromCache: UIImage?
        _ = loader.loadThumbnail(id: "cache-me", targetSize: CGSize(width: 32, height: 32)) { image in
            receivedFromCache = image
            secondExpectation.fulfill()
        }
        wait(for: [secondExpectation], timeout: 2)

        XCTAssertEqual(store.loadCalls.count, 1, "Second load should hit cache, not store")
        XCTAssertNotNil(receivedFromCache)
    }

    func test_loadThumbnail_memoryWarning_evictsCache() {
        store.stubbedImage = makeImage(size: CGSize(width: 200, height: 200))

        let firstExpectation = expectation(description: "first load")
        _ = loader.loadThumbnail(id: "evictable", targetSize: CGSize(width: 32, height: 32)) { _ in
            firstExpectation.fulfill()
        }
        wait(for: [firstExpectation], timeout: 2)

        NotificationCenter.default.post(
            name: UIApplication.didReceiveMemoryWarningNotification,
            object: nil
        )

        let secondExpectation = expectation(description: "second load")
        _ = loader.loadThumbnail(id: "evictable", targetSize: CGSize(width: 32, height: 32)) { _ in
            secondExpectation.fulfill()
        }
        wait(for: [secondExpectation], timeout: 2)

        XCTAssertEqual(store.loadCalls.count, 2, "Memory warning should evict cache; second load must hit store again")
    }

    func test_loadThumbnail_token_cancel_preventsCompletion() {
        let queue = DispatchQueue(label: "test-blocking")
        queue.suspend()
        let blockingLoader = ThumbnailLoader(store: store, processingQueue: queue)
        store.stubbedImage = makeImage(size: CGSize(width: 100, height: 100))

        let completionShouldNotFire = expectation(description: "completion not fired")
        completionShouldNotFire.isInverted = true

        let token = blockingLoader.loadThumbnail(
            id: "soon-cancelled",
            targetSize: CGSize(width: 32, height: 32)
        ) { _ in
            completionShouldNotFire.fulfill()
        }
        token.cancel()
        queue.resume()

        wait(for: [completionShouldNotFire], timeout: 0.5)
    }

    func test_loadThumbnail_completion_firesOnMainQueue() {
        store.stubbedImage = makeImage(size: CGSize(width: 100, height: 100))

        let expectation = expectation(description: "main queue completion")
        _ = loader.loadThumbnail(id: "main-test", targetSize: CGSize(width: 32, height: 32)) { _ in
            XCTAssertTrue(Thread.isMainThread, "Completion must fire on main queue")
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 2)
    }

    // MARK: - Helpers

    private func makeImage(size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.purple.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

// MARK: - Test doubles

private final class SpyImageAssetStore: ImageAssetStoring {
    var stubbedImage: UIImage?
    private(set) var loadCalls: [String] = []

    func save(_ image: UIImage) throws -> String { UUID().uuidString }

    func load(id: String) -> UIImage? {
        loadCalls.append(id)
        return stubbedImage
    }

    func delete(id: String) throws {}
    func deleteAll() throws {}
    func allAssetIDs() -> [String] { [] }
}
