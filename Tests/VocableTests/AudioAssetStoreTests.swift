//
//  AudioAssetStoreTests.swift
//  VocableTests
//

import XCTest
@testable import Vocable

final class AudioAssetStoreTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var store: AudioAssetStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioAssetStoreTests")
            .appendingPathComponent(UUID().uuidString)
        store = try AudioAssetStore(baseDirectory: temporaryDirectory)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_init_createsDirectoryIfMissing() {
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporaryDirectory.path))
    }

    func test_save_returnsStableUUIDAssetID() throws {
        let data = sampleData()
        let id1 = try store.save(data)
        let id2 = try store.save(data)
        XCTAssertNotEqual(id1, id2)
        XCTAssertNotNil(UUID(uuidString: id1))
        XCTAssertNotNil(UUID(uuidString: id2))
    }

    func test_save_thenLoad_returnsSameBytes() throws {
        let data = sampleData()
        let id = try store.save(data)
        let loaded = try XCTUnwrap(store.load(id: id))
        XCTAssertEqual(loaded, data)
    }

    func test_load_unknownID_returnsNil() {
        XCTAssertNil(store.load(id: UUID().uuidString))
    }

    func test_url_forKnownID_returnsExistingFile() throws {
        let id = try store.save(sampleData())
        let url = try XCTUnwrap(store.url(for: id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(url.pathExtension, "m4a")
    }

    func test_url_forUnknownID_returnsNil() {
        XCTAssertNil(store.url(for: UUID().uuidString))
    }

    func test_delete_removesFile_subsequentLoadReturnsNil() throws {
        let id = try store.save(sampleData())
        XCTAssertNotNil(store.load(id: id))
        try store.delete(id: id)
        XCTAssertNil(store.load(id: id))
        XCTAssertNil(store.url(for: id))
    }

    func test_delete_unknownID_doesNotThrow() {
        XCTAssertNoThrow(try store.delete(id: UUID().uuidString))
    }

    func test_save_writesToM4AExtension_underBaseDirectory() throws {
        let id = try store.save(sampleData())
        let expectedURL = temporaryDirectory.appendingPathComponent("\(id).m4a")
        XCTAssertTrue(FileManager.default.fileExists(atPath: expectedURL.path))
    }

    func test_listAllAssetIDs_returnsAllOnDiskIDs() throws {
        let id1 = try store.save(sampleData())
        let id2 = try store.save(sampleData())
        let id3 = try store.save(sampleData())
        XCTAssertEqual(Set(store.allAssetIDs()), Set([id1, id2, id3]))
    }

    func test_listAllAssetIDs_excludesNonM4AFiles() throws {
        _ = try store.save(sampleData())
        let strayURL = temporaryDirectory.appendingPathComponent("notes.txt")
        try Data("hi".utf8).write(to: strayURL)
        XCTAssertEqual(store.allAssetIDs().count, 1)
    }

    func test_deleteAll_emptiesDirectory() throws {
        _ = try store.save(sampleData())
        _ = try store.save(sampleData())
        _ = try store.save(sampleData())
        XCTAssertEqual(store.allAssetIDs().count, 3)
        try store.deleteAll()
        XCTAssertEqual(store.allAssetIDs().count, 0)
    }

    func test_defaultDirectory_resolvesUnderApplicationSupportRecordings() {
        let url = AudioAssetStore.defaultDirectory
        XCTAssertEqual(url.lastPathComponent, "Recordings")
        XCTAssertTrue(url.path.contains("Application Support"))
    }

    // MARK: - Helpers

    private func sampleData(length: Int = 256) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(length)
        for i in 0..<length {
            bytes.append(UInt8(i & 0xFF))
        }
        return Data(bytes)
    }
}
