//
//  ImageAssetStoreTests.swift
//  VocableTests
//

import XCTest
import UIKit
@testable import Vocable

final class ImageAssetStoreTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var store: ImageAssetStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ImageAssetStoreTests")
            .appendingPathComponent(UUID().uuidString)
        // Intentionally do NOT precreate; let init create it.
        store = try ImageAssetStore(baseDirectory: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_init_createsDirectoryIfMissing() {
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: temporaryDirectory.path),
            "init should create the base directory"
        )
    }

    func test_save_returnsStableUUIDAssetID() throws {
        let image = makeTestImage()
        let id1 = try store.save(image)
        let id2 = try store.save(image)
        XCTAssertNotEqual(id1, id2, "Each save should produce a distinct ID")
        XCTAssertNotNil(UUID(uuidString: id1), "ID should be a valid UUID string")
        XCTAssertNotNil(UUID(uuidString: id2), "ID should be a valid UUID string")
    }

    func test_save_thenLoadByID_returnsEquivalentImage() throws {
        let original = makeTestImage(size: CGSize(width: 100, height: 100))
        let id = try store.save(original)
        let loaded = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(loaded.size, original.size, "Loaded image dimensions should match")
    }

    func test_load_unknownID_returnsNil() {
        XCTAssertNil(store.load(id: UUID().uuidString))
    }

    func test_delete_removesFile_subsequentLoadReturnsNil() throws {
        let id = try store.save(makeTestImage())
        XCTAssertNotNil(store.load(id: id))
        try store.delete(id: id)
        XCTAssertNil(store.load(id: id))
    }

    func test_delete_unknownID_doesNotThrow() {
        XCTAssertNoThrow(try store.delete(id: UUID().uuidString))
    }

    func test_save_writesToBaseDirectory() throws {
        let id = try store.save(makeTestImage())
        let expectedURL = temporaryDirectory.appendingPathComponent("\(id).jpg")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: expectedURL.path),
            "Expected file at \(expectedURL.path)"
        )
    }

    func test_save_persistsAsJPEG_magicBytes() throws {
        let id = try store.save(makeTestImage())
        let url = temporaryDirectory.appendingPathComponent("\(id).jpg")
        let data = try Data(contentsOf: url)
        XCTAssertEqual(
            Array(data.prefix(3)),
            [0xFF, 0xD8, 0xFF],
            "File should begin with JPEG magic bytes"
        )
    }

    func test_listAllAssetIDs_returnsAllOnDiskIDs() throws {
        let id1 = try store.save(makeTestImage())
        let id2 = try store.save(makeTestImage())
        let id3 = try store.save(makeTestImage())
        let all = Set(store.allAssetIDs())
        XCTAssertEqual(all, Set([id1, id2, id3]))
    }

    func test_listAllAssetIDs_excludesNonJPEGFiles() throws {
        _ = try store.save(makeTestImage())
        let strayURL = temporaryDirectory.appendingPathComponent("not-an-asset.txt")
        try Data("hello".utf8).write(to: strayURL)
        XCTAssertEqual(store.allAssetIDs().count, 1)
    }

    func test_defaultDirectory_resolvesUnderApplicationSupportPhraseImages() {
        let url = ImageAssetStore.defaultDirectory
        XCTAssertEqual(url.lastPathComponent, "PhraseImages")
        XCTAssertTrue(
            url.path.contains("Application Support"),
            "Default directory should live under Application Support, got: \(url.path)"
        )
    }

    // MARK: - Helpers

    private func makeTestImage(size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.red.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
