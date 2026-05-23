//
//  AudioLifecycleObserverTests.swift
//  VocableTests
//

import XCTest
import CoreData
@testable import Vocable

final class AudioLifecycleObserverTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var store: AudioAssetStore!
    private var context: NSManagedObjectContext!
    private var observer: AudioLifecycleObserver!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("AudioLifecycleObserverTests")
            .appendingPathComponent(UUID().uuidString)
        store = try AudioAssetStore(baseDirectory: temporaryDirectory)
        context = try makeInMemoryContext()
        observer = AudioLifecycleObserver(context: context, store: store)
    }

    override func tearDownWithError() throws {
        observer = nil
        context = nil
        store = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_deletingPhrase_withAudioAsset_deletesUnderlyingFile() throws {
        let category = makeCategory()
        let phrase = makePhrase(category: category)
        let assetID = try store.save(sampleAudioData())
        phrase.setValue(assetID, forKey: "audioAssetID")
        try context.save()

        XCTAssertNotNil(store.load(id: assetID))

        context.delete(phrase)
        try context.save()

        XCTAssertNil(store.load(id: assetID),
                     "Phrase delete should remove its recording")
    }

    func test_reassigningAudioAssetID_deletesPreviousFile() throws {
        let category = makeCategory()
        let phrase = makePhrase(category: category)
        let oldID = try store.save(sampleAudioData())
        phrase.setValue(oldID, forKey: "audioAssetID")
        try context.save()

        XCTAssertNotNil(store.load(id: oldID))

        let newID = try store.save(sampleAudioData())
        phrase.setValue(newID, forKey: "audioAssetID")
        try context.save()

        XCTAssertNil(store.load(id: oldID),
                     "Previous recording should be deleted on reassignment")
        XCTAssertNotNil(store.load(id: newID))
    }

    func test_sweepOrphans_deletesUnreferencedAudioAssets() throws {
        let category = makeCategory()
        let phrase = makePhrase(category: category)
        let referencedID = try store.save(sampleAudioData())
        phrase.setValue(referencedID, forKey: "audioAssetID")
        try context.save()

        let orphanID = try store.save(sampleAudioData())

        try observer.sweepOrphans()

        XCTAssertNotNil(store.load(id: referencedID))
        XCTAssertNil(store.load(id: orphanID))
    }

    func test_sweepOrphans_doesNotDeleteReferencedAudioAssets() throws {
        let category = makeCategory()
        let phrase = makePhrase(category: category)
        let assetID = try store.save(sampleAudioData())
        phrase.setValue(assetID, forKey: "audioAssetID")
        try context.save()

        try observer.sweepOrphans()

        XCTAssertNotNil(store.load(id: assetID))
    }

    // MARK: - Helpers

    private func makeInMemoryContext() throws -> NSManagedObjectContext {
        let momdURL = try locateMomdURL()
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        try coordinator.addPersistentStore(
            ofType: NSInMemoryStoreType,
            configurationName: nil,
            at: nil,
            options: nil
        )
        let ctx = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        ctx.persistentStoreCoordinator = coordinator
        return ctx
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
        throw NSError(domain: "AudioLifecycleObserverTests", code: -1)
    }

    @discardableResult
    private func makeCategory() -> NSManagedObject {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("c1", forKey: "identifier")
        category.setValue("Test", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")
        return category
    }

    @discardableResult
    private func makePhrase(category: NSManagedObject) -> NSManagedObject {
        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("hello", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue(category, forKey: "category")
        return phrase
    }

    private func sampleAudioData(length: Int = 128) -> Data {
        var bytes: [UInt8] = []
        bytes.reserveCapacity(length)
        for i in 0..<length {
            bytes.append(UInt8(i & 0xFF))
        }
        return Data(bytes)
    }
}
