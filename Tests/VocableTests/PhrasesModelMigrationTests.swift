//
//  PhrasesModelMigrationTests.swift
//  VocableTests
//
//  Verifies Phrases v4 → v5 lightweight migration adds an
//  optional imageAssetID attribute to Phrase and Category
//  without data loss.
//

import XCTest
import CoreData
@testable import Vocable

final class PhrasesModelMigrationTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhrasesModelMigrationTests")
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
        storeURL = temporaryDirectory.appendingPathComponent("Phrases.sqlite")
    }

    override func tearDownWithError() throws {
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_loadingV4Store_migratesToV5_withoutDataLoss() throws {
        let v4Model = try loadModel(version: .v4)
        let currentModel = try loadModel(version: .current)

        XCTAssertNotEqual(
            v4Model.entityVersionHashesByName,
            currentModel.entityVersionHashesByName,
            "Current model should differ from v4 — add Phrases v5 with imageAssetID"
        )

        let seedContext = try makeContext(model: v4Model, at: storeURL)
        try seedV4Data(
            in: seedContext,
            categoryIdentifier: "cat-1",
            categoryName: "Drinks",
            phraseIdentifier: "phrase-1",
            utterance: "cup"
        )
        try seedContext.save()
        try tearDownContext(seedContext)

        let migratedContext = try makeContext(model: currentModel, at: storeURL)

        let categories = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Category"))
        XCTAssertEqual(categories.count, 1)
        XCTAssertEqual(categories.first?.value(forKey: "identifier") as? String, "cat-1")
        XCTAssertEqual(categories.first?.value(forKey: "name") as? String, "Drinks")

        let phrases = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase"))
        XCTAssertEqual(phrases.count, 1)
        XCTAssertEqual(phrases.first?.value(forKey: "identifier") as? String, "phrase-1")
        XCTAssertEqual(phrases.first?.value(forKey: "utterance") as? String, "cup")
    }

    func test_migratedV5_phrasesAndCategories_haveNilImageAssetID() throws {
        let v4Model = try loadModel(version: .v4)
        let currentModel = try loadModel(version: .current)

        let seedContext = try makeContext(model: v4Model, at: storeURL)
        try seedV4Data(
            in: seedContext,
            categoryIdentifier: "c1",
            categoryName: "Drinks",
            phraseIdentifier: "p1",
            utterance: "milk"
        )
        try seedContext.save()
        try tearDownContext(seedContext)

        let migratedContext = try makeContext(model: currentModel, at: storeURL)
        let category = try XCTUnwrap(
            migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Category")).first
        )
        let phrase = try XCTUnwrap(
            migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase")).first
        )

        XCTAssertNotNil(
            category.entity.attributesByName["imageAssetID"],
            "Category entity should declare imageAssetID in v5"
        )
        XCTAssertNotNil(
            phrase.entity.attributesByName["imageAssetID"],
            "Phrase entity should declare imageAssetID in v5"
        )

        XCTAssertNil(category.value(forKey: "imageAssetID"))
        XCTAssertNil(phrase.value(forKey: "imageAssetID"))
    }

    func test_v5_canSetAndPersistImageAssetID_onPhrase() throws {
        let currentModel = try loadModel(version: .current)
        let context = try makeContext(model: currentModel, at: storeURL)

        // Phrase.category is a required relationship in the schema — create a parent.
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("parent-cat", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        guard phrase.entity.attributesByName["imageAssetID"] != nil else {
            XCTFail("Phrase entity is missing imageAssetID attribute — add Phrases v5 model")
            return
        }
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("cup", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue("asset-abc-123", forKey: "imageAssetID")
        phrase.setValue(category, forKey: "category")
        try context.save()
        try tearDownContext(context)

        let reloaded = try makeContext(model: currentModel, at: storeURL)
        let fetched = try XCTUnwrap(
            reloaded.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase")).first
        )
        XCTAssertEqual(fetched.value(forKey: "imageAssetID") as? String, "asset-abc-123")
    }

    func test_v5_canSetAndPersistImageAssetID_onCategory() throws {
        let currentModel = try loadModel(version: .current)
        let context = try makeContext(model: currentModel, at: storeURL)

        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        guard category.entity.attributesByName["imageAssetID"] != nil else {
            XCTFail("Category entity is missing imageAssetID attribute — add Phrases v5 model")
            return
        }
        category.setValue("c1", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")
        category.setValue("asset-xyz-789", forKey: "imageAssetID")
        try context.save()
        try tearDownContext(context)

        let reloaded = try makeContext(model: currentModel, at: storeURL)
        let fetched = try XCTUnwrap(
            reloaded.fetch(NSFetchRequest<NSManagedObject>(entityName: "Category")).first
        )
        XCTAssertEqual(fetched.value(forKey: "imageAssetID") as? String, "asset-xyz-789")
    }

    // MARK: - Helpers

    private enum ModelVersion {
        case v4
        case current
    }

    private func loadModel(version: ModelVersion) throws -> NSManagedObjectModel {
        let momdURL = try locateMomdURL()
        switch version {
        case .current:
            return try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        case .v4:
            let v4URL = momdURL.appendingPathComponent("Phrases v4.mom")
            return try XCTUnwrap(
                NSManagedObjectModel(contentsOf: v4URL),
                "Could not load Phrases v4.mom — check that v4 is preserved in xcdatamodeld"
            )
        }
    }

    private func locateMomdURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "Phrases", withExtension: "momd") {
            return url
        }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "Phrases", withExtension: "momd") {
                return url
            }
        }
        for bundle in Bundle.allFrameworks {
            if let url = bundle.url(forResource: "Phrases", withExtension: "momd") {
                return url
            }
        }
        XCTFail("Could not locate Phrases.momd in any loaded bundle")
        throw NSError(domain: "PhrasesModelMigrationTests", code: -1)
    }

    private func makeContext(model: NSManagedObjectModel, at storeURL: URL) throws -> NSManagedObjectContext {
        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: model)
        let options: [String: Any] = [
            NSMigratePersistentStoresAutomaticallyOption: true,
            NSInferMappingModelAutomaticallyOption: true
        ]
        try coordinator.addPersistentStore(
            ofType: NSSQLiteStoreType,
            configurationName: nil,
            at: storeURL,
            options: options
        )
        let context = NSManagedObjectContext(concurrencyType: .mainQueueConcurrencyType)
        context.persistentStoreCoordinator = coordinator
        return context
    }

    private func tearDownContext(_ context: NSManagedObjectContext) throws {
        guard let coordinator = context.persistentStoreCoordinator else { return }
        for store in coordinator.persistentStores {
            try coordinator.remove(store)
        }
    }

    private func seedV4Data(
        in context: NSManagedObjectContext,
        categoryIdentifier: String,
        categoryName: String,
        phraseIdentifier: String,
        utterance: String
    ) throws {
        let now = Date()
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue(categoryIdentifier, forKey: "identifier")
        category.setValue(categoryName, forKey: "name")
        category.setValue(now, forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        phrase.setValue(phraseIdentifier, forKey: "identifier")
        phrase.setValue(utterance, forKey: "utterance")
        phrase.setValue(now, forKey: "creationDate")
        phrase.setValue(category, forKey: "category")
    }
}
