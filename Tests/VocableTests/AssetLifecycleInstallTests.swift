//
//  AssetLifecycleInstallTests.swift
//  VocableTests
//
//  Exercises NSPersistentContainer.installAssetLifecycleObservers — the
//  wiring that ensures phrase deletions and assetID reassignments
//  actually clean up underlying photo + audio files in production.
//

import XCTest
import CoreData
import UIKit
@testable import Vocable

final class AssetLifecycleInstallTests: XCTestCase {

    private var imageDirectory: URL!
    private var audioDirectory: URL!
    private var imageStore: ImageAssetStore!
    private var audioStore: AudioAssetStore!
    private var container: NSPersistentContainer!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("AssetLifecycleInstallTests")
            .appendingPathComponent(UUID().uuidString)
        imageDirectory = root.appendingPathComponent("Images")
        audioDirectory = root.appendingPathComponent("Audio")
        imageStore = try ImageAssetStore(baseDirectory: imageDirectory)
        audioStore = try AudioAssetStore(baseDirectory: audioDirectory)
        container = try makeInMemoryContainer()
    }

    override func tearDownWithError() throws {
        container = nil
        imageStore = nil
        audioStore = nil
        let root = imageDirectory.deletingLastPathComponent()
        try? FileManager.default.removeItem(at: root)
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_install_returnsBothObservers() {
        let observers = NSPersistentContainer.installAssetLifecycleObservers(
            on: container,
            imageStore: imageStore,
            audioStore: audioStore
        )
        XCTAssertNotNil(observers.0)
        XCTAssertNotNil(observers.1)
    }

    func test_install_runsInitialOrphanSweep_onBothStores() throws {
        // Pre-populate the stores with orphan files (no Core Data row references them).
        let orphanImage = try imageStore.save(testImage())
        let orphanAudio = try audioStore.save(testAudioBytes())

        XCTAssertNotNil(imageStore.load(id: orphanImage))
        XCTAssertNotNil(audioStore.load(id: orphanAudio))

        _ = NSPersistentContainer.installAssetLifecycleObservers(
            on: container,
            imageStore: imageStore,
            audioStore: audioStore
        )

        XCTAssertNil(imageStore.load(id: orphanImage),
                     "Image orphan should be swept on observer install")
        XCTAssertNil(audioStore.load(id: orphanAudio),
                     "Audio orphan should be swept on observer install")
    }

    func test_install_attachesObserversThatFire_onPhraseDelete() throws {
        // Capture the observers (they need to be alive for notifications to fire).
        let observers = NSPersistentContainer.installAssetLifecycleObservers(
            on: container,
            imageStore: imageStore,
            audioStore: audioStore
        )
        XCTAssertNotNil(observers.0)    // retain through test
        XCTAssertNotNil(observers.1)

        let context = container.viewContext

        // Create a phrase with both a photo and a recording attached.
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("cat-1", forKey: "identifier")
        category.setValue("Test", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("hello", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue(category, forKey: "category")

        let imageAssetID = try imageStore.save(testImage())
        let audioAssetID = try audioStore.save(testAudioBytes())
        phrase.setValue(imageAssetID, forKey: "imageAssetID")
        phrase.setValue(audioAssetID, forKey: "audioAssetID")
        try context.save()

        XCTAssertNotNil(imageStore.load(id: imageAssetID))
        XCTAssertNotNil(audioStore.load(id: audioAssetID))

        // Delete and save — observers should pick up the deletion and remove both files.
        context.delete(phrase)
        try context.save()

        XCTAssertNil(imageStore.load(id: imageAssetID),
                     "Phrase delete should remove the photo file via the installed observer")
        XCTAssertNil(audioStore.load(id: audioAssetID),
                     "Phrase delete should remove the audio file via the installed observer")
    }

    func test_install_attachesObserversThatFire_onAssetIDReassignment() throws {
        let observers = NSPersistentContainer.installAssetLifecycleObservers(
            on: container,
            imageStore: imageStore,
            audioStore: audioStore
        )
        XCTAssertNotNil(observers.0)
        XCTAssertNotNil(observers.1)

        let context = container.viewContext
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("cat-1", forKey: "identifier")
        category.setValue("Test", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("hi", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue(category, forKey: "category")

        let firstID = try imageStore.save(testImage())
        phrase.setValue(firstID, forKey: "imageAssetID")
        try context.save()

        // Reassign — the previous file should be cleaned up.
        let secondID = try imageStore.save(testImage())
        phrase.setValue(secondID, forKey: "imageAssetID")
        try context.save()

        XCTAssertNil(imageStore.load(id: firstID),
                     "Reassignment should remove the previous photo file")
        XCTAssertNotNil(imageStore.load(id: secondID),
                        "New photo file should remain")
    }

    // MARK: - Helpers

    private func makeInMemoryContainer() throws -> NSPersistentContainer {
        let momdURL = try locateMomdURL()
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        let container = NSPersistentContainer(name: "Phrases", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }

    private func locateMomdURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "Phrases", withExtension: "momd") { return url }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "Phrases", withExtension: "momd") { return url }
        }
        for bundle in Bundle.allFrameworks {
            if let url = bundle.url(forResource: "Phrases", withExtension: "momd") { return url }
        }
        XCTFail("Could not locate Phrases.momd")
        throw NSError(domain: "AssetLifecycleInstallTests", code: -1)
    }

    private func testImage(size: CGSize = CGSize(width: 16, height: 16)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.green.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func testAudioBytes() -> Data {
        var bytes: [UInt8] = []
        for i in 0..<128 { bytes.append(UInt8(i & 0xFF)) }
        return Data(bytes)
    }
}
