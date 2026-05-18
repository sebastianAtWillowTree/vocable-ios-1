//
//  PhotoLifecycleObserverTests.swift
//  VocableTests
//

import XCTest
import CoreData
import UIKit
@testable import Vocable

final class PhotoLifecycleObserverTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var store: ImageAssetStore!
    private var context: NSManagedObjectContext!
    private var observer: PhotoLifecycleObserver!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhotoLifecycleObserverTests")
            .appendingPathComponent(UUID().uuidString)
        store = try ImageAssetStore(baseDirectory: temporaryDirectory)
        context = try makeInMemoryContext()
        observer = PhotoLifecycleObserver(context: context, store: store)
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

    func test_deletingPhrase_withImageAsset_deletesUnderlyingFile() throws {
        let category = makeCategory(identifier: "c1")
        let phrase = makePhrase(identifier: "p1", category: category)
        let assetID = try store.save(makeTestImage())
        phrase.setValue(assetID, forKey: "imageAssetID")
        try context.save()

        XCTAssertNotNil(store.load(id: assetID))

        context.delete(phrase)
        try context.save()

        XCTAssertNil(store.load(id: assetID), "Phrase delete should remove its image file")
    }

    func test_deletingCategory_withImageAsset_deletesUnderlyingFile() throws {
        let category = makeCategory(identifier: "c1")
        let assetID = try store.save(makeTestImage())
        category.setValue(assetID, forKey: "imageAssetID")
        try context.save()

        XCTAssertNotNil(store.load(id: assetID))

        context.delete(category)
        try context.save()

        XCTAssertNil(store.load(id: assetID), "Category delete should remove its image file")
    }

    func test_reassigningImageAssetID_deletesPreviousFile() throws {
        let category = makeCategory(identifier: "c1")
        let phrase = makePhrase(identifier: "p1", category: category)
        let oldID = try store.save(makeTestImage())
        phrase.setValue(oldID, forKey: "imageAssetID")
        try context.save()

        XCTAssertNotNil(store.load(id: oldID))

        let newID = try store.save(makeTestImage())
        phrase.setValue(newID, forKey: "imageAssetID")
        try context.save()

        XCTAssertNil(store.load(id: oldID), "Previous image file should be deleted on reassignment")
        XCTAssertNotNil(store.load(id: newID), "New image file should remain")
    }

    func test_sweepOrphans_deletesFilesNotReferencedByAnyEntity() throws {
        // Save a referenced asset and an orphan.
        let category = makeCategory(identifier: "c1")
        let referencedID = try store.save(makeTestImage())
        category.setValue(referencedID, forKey: "imageAssetID")
        try context.save()

        let orphanID = try store.save(makeTestImage())

        try observer.sweepOrphans()

        XCTAssertNotNil(store.load(id: referencedID), "Referenced asset should remain")
        XCTAssertNil(store.load(id: orphanID), "Orphan asset should be removed")
    }

    func test_sweepOrphans_doesNotDeleteReferencedFiles() throws {
        let category = makeCategory(identifier: "c1")
        let categoryAssetID = try store.save(makeTestImage())
        category.setValue(categoryAssetID, forKey: "imageAssetID")

        let phrase = makePhrase(identifier: "p1", category: category)
        let phraseAssetID = try store.save(makeTestImage())
        phrase.setValue(phraseAssetID, forKey: "imageAssetID")

        try context.save()

        try observer.sweepOrphans()

        XCTAssertNotNil(store.load(id: categoryAssetID))
        XCTAssertNotNil(store.load(id: phraseAssetID))
    }

    func test_store_deleteAll_emptiesDirectory() throws {
        _ = try store.save(makeTestImage())
        _ = try store.save(makeTestImage())
        _ = try store.save(makeTestImage())
        XCTAssertEqual(store.allAssetIDs().count, 3)

        try store.deleteAll()

        XCTAssertEqual(store.allAssetIDs().count, 0)
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
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
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
        throw NSError(domain: "PhotoLifecycleObserverTests", code: -1)
    }

    @discardableResult
    private func makeCategory(identifier: String) -> NSManagedObject {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue(identifier, forKey: "identifier")
        category.setValue("TestCategory-\(identifier)", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")
        return category
    }

    @discardableResult
    private func makePhrase(identifier: String, category: NSManagedObject) -> NSManagedObject {
        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        phrase.setValue(identifier, forKey: "identifier")
        phrase.setValue("utterance-\(identifier)", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue(category, forKey: "category")
        return phrase
    }

    private func makeTestImage(size: CGSize = CGSize(width: 16, height: 16)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            UIColor.blue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
