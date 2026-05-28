//
//  PhrasesV7MigrationTests.swift
//  VocableTests
//
//  Verifies Phrases v6 → v7 lightweight migration adds the optional
//  cartoonPrompt attribute to Phrase without touching Category.
//

import XCTest
import CoreData
@testable import Vocable

final class PhrasesV7MigrationTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhrasesV7MigrationTests")
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

    func test_loadingV6Store_migratesToV7_withoutDataLoss() throws {
        let v6Model = try loadModel(version: .v6)
        let currentModel = try loadModel(version: .current)

        XCTAssertNotEqual(
            v6Model.entityVersionHashesByName,
            currentModel.entityVersionHashesByName,
            "Current model should differ from v6 — add Phrases v7 with cartoonPrompt"
        )

        let seedContext = try makeContext(model: v6Model, at: storeURL)
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: seedContext)
        category.setValue("cat-v6", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")
        category.setValue("img-cat", forKey: "imageAssetID")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: seedContext)
        phrase.setValue("phrase-v6", forKey: "identifier")
        phrase.setValue("hello", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue("img-phrase", forKey: "imageAssetID")
        phrase.setValue("audio-phrase", forKey: "audioAssetID")
        phrase.setValue(true, forKey: "prefersRecording")
        phrase.setValue(category, forKey: "category")
        try seedContext.save()
        try tearDownContext(seedContext)

        let migratedContext = try makeContext(model: currentModel, at: storeURL)
        let migratedPhrase = try XCTUnwrap(
            migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase")).first
        )

        XCTAssertEqual(migratedPhrase.value(forKey: "imageAssetID") as? String, "img-phrase")
        XCTAssertEqual(migratedPhrase.value(forKey: "audioAssetID") as? String, "audio-phrase")
        XCTAssertEqual(migratedPhrase.value(forKey: "prefersRecording") as? Bool, true)
        XCTAssertEqual(migratedPhrase.value(forKey: "utterance") as? String, "hello")
    }

    func test_migratedV7_phrases_haveNilCartoonPrompt() throws {
        let v6Model = try loadModel(version: .v6)
        let currentModel = try loadModel(version: .current)

        let seedContext = try makeContext(model: v6Model, at: storeURL)
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: seedContext)
        category.setValue("c1", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: seedContext)
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("hi", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue(category, forKey: "category")
        try seedContext.save()
        try tearDownContext(seedContext)

        let migratedContext = try makeContext(model: currentModel, at: storeURL)
        let migrated = try XCTUnwrap(
            migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase")).first
        )

        XCTAssertNotNil(migrated.entity.attributesByName["cartoonPrompt"],
                        "Phrase entity should declare cartoonPrompt in v7")
        XCTAssertNil(migrated.value(forKey: "cartoonPrompt"),
                     "Migrated phrases should have nil cartoonPrompt")
    }

    func test_v7_canSetAndPersistCartoonPrompt_onPhrase() throws {
        let currentModel = try loadModel(version: .current)
        let context = try makeContext(model: currentModel, at: storeURL)

        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("parent-cat", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        guard phrase.entity.attributesByName["cartoonPrompt"] != nil else {
            XCTFail("Phrase entity is missing cartoonPrompt — add Phrases v7 model")
            return
        }
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("cup", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue("a friendly cup with steam coming out", forKey: "cartoonPrompt")
        phrase.setValue(category, forKey: "category")
        try context.save()
        try tearDownContext(context)

        let reloaded = try makeContext(model: currentModel, at: storeURL)
        let fetched = try XCTUnwrap(
            reloaded.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase")).first
        )
        XCTAssertEqual(
            fetched.value(forKey: "cartoonPrompt") as? String,
            "a friendly cup with steam coming out"
        )
    }

    func test_v7_category_doesNotDeclare_cartoonPrompt() throws {
        let currentModel = try loadModel(version: .current)
        let context = try makeContext(model: currentModel, at: storeURL)
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        XCTAssertNil(
            category.entity.attributesByName["cartoonPrompt"],
            "Category must not gain cartoonPrompt — cartoonify is phrase-only"
        )
    }

    // MARK: - Helpers

    private enum ModelVersion {
        case v6
        case current
    }

    private func loadModel(version: ModelVersion) throws -> NSManagedObjectModel {
        let momdURL = try locateMomdURL()
        switch version {
        case .current:
            return try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        case .v6:
            let url = momdURL.appendingPathComponent("Phrases v6.mom")
            return try XCTUnwrap(
                NSManagedObjectModel(contentsOf: url),
                "Could not load Phrases v6.mom — check that v6 is preserved in xcdatamodeld"
            )
        }
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
        throw NSError(domain: "PhrasesV7MigrationTests", code: -1)
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
}
