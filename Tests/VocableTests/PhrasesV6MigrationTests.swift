//
//  PhrasesV6MigrationTests.swift
//  VocableTests
//
//  Verifies Phrases v5 → v6 lightweight migration adds the
//  audio attributes (audioAssetID + prefersRecording) to Phrase
//  without data loss and without modifying Category.
//

import XCTest
import CoreData
@testable import Vocable

final class PhrasesV6MigrationTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var storeURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhrasesV6MigrationTests")
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

    func test_loadingV5Store_migratesToV6_withoutDataLoss() throws {
        let v5Model = try loadModel(version: .v5)
        let currentModel = try loadModel(version: .current)

        XCTAssertNotEqual(
            v5Model.entityVersionHashesByName,
            currentModel.entityVersionHashesByName,
            "Current model should differ from v5 — add Phrases v6 with audio attributes"
        )

        // Seed a v5 store with a category + phrase, including the v5 imageAssetID.
        let seedContext = try makeContext(model: v5Model, at: storeURL)
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: seedContext)
        category.setValue("cat-v5", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")
        category.setValue("asset-cat-photo", forKey: "imageAssetID")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: seedContext)
        phrase.setValue("phrase-v5", forKey: "identifier")
        phrase.setValue("hello", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue("asset-phrase-photo", forKey: "imageAssetID")
        phrase.setValue(category, forKey: "category")

        try seedContext.save()
        try tearDownContext(seedContext)

        let migratedContext = try makeContext(model: currentModel, at: storeURL)

        let phrases = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase"))
        XCTAssertEqual(phrases.count, 1)
        let migratedPhrase = try XCTUnwrap(phrases.first)
        XCTAssertEqual(migratedPhrase.value(forKey: "identifier") as? String, "phrase-v5")
        XCTAssertEqual(migratedPhrase.value(forKey: "utterance") as? String, "hello")
        XCTAssertEqual(migratedPhrase.value(forKey: "imageAssetID") as? String, "asset-phrase-photo",
                       "v5 imageAssetID should survive migration to v6")

        let categories = try migratedContext.fetch(NSFetchRequest<NSManagedObject>(entityName: "Category"))
        XCTAssertEqual(categories.count, 1)
        let migratedCategory = try XCTUnwrap(categories.first)
        XCTAssertEqual(migratedCategory.value(forKey: "imageAssetID") as? String, "asset-cat-photo")
    }

    func test_migratedV6_phrases_haveNilAudioAssetID_andPrefersRecordingFalse() throws {
        let v5Model = try loadModel(version: .v5)
        let currentModel = try loadModel(version: .current)

        let seedContext = try makeContext(model: v5Model, at: storeURL)
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

        XCTAssertNotNil(migrated.entity.attributesByName["audioAssetID"],
                        "Phrase entity should declare audioAssetID in v6")
        XCTAssertNotNil(migrated.entity.attributesByName["prefersRecording"],
                        "Phrase entity should declare prefersRecording in v6")

        XCTAssertNil(migrated.value(forKey: "audioAssetID"))
        XCTAssertEqual(migrated.value(forKey: "prefersRecording") as? Bool, false,
                       "prefersRecording should default to NO on migrated rows")
    }

    func test_v6_canSetAndPersistAudioAssetID_onPhrase() throws {
        let currentModel = try loadModel(version: .current)
        let context = try makeContext(model: currentModel, at: storeURL)

        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("parent-cat", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        guard phrase.entity.attributesByName["audioAssetID"] != nil else {
            XCTFail("Phrase entity is missing audioAssetID — add Phrases v6 model")
            return
        }
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("cup", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue("audio-asset-789", forKey: "audioAssetID")
        phrase.setValue(true, forKey: "prefersRecording")
        phrase.setValue(category, forKey: "category")
        try context.save()
        try tearDownContext(context)

        let reloaded = try makeContext(model: currentModel, at: storeURL)
        let fetched = try XCTUnwrap(
            reloaded.fetch(NSFetchRequest<NSManagedObject>(entityName: "Phrase")).first
        )
        XCTAssertEqual(fetched.value(forKey: "audioAssetID") as? String, "audio-asset-789")
        XCTAssertEqual(fetched.value(forKey: "prefersRecording") as? Bool, true)
    }

    func test_v6_category_doesNotDeclare_audioAssetID() throws {
        let currentModel = try loadModel(version: .current)
        let context = try makeContext(model: currentModel, at: storeURL)
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)

        XCTAssertNil(category.entity.attributesByName["audioAssetID"],
                     "Category must not gain audioAssetID — voice recording is phrase-only for now")
        XCTAssertNil(category.entity.attributesByName["prefersRecording"],
                     "Category must not gain prefersRecording — voice recording is phrase-only for now")
    }

    // MARK: - Helpers

    private enum ModelVersion {
        case v5
        case current
    }

    private func loadModel(version: ModelVersion) throws -> NSManagedObjectModel {
        let momdURL = try locateMomdURL()
        switch version {
        case .current:
            return try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        case .v5:
            let v5URL = momdURL.appendingPathComponent("Phrases v5.mom")
            return try XCTUnwrap(
                NSManagedObjectModel(contentsOf: v5URL),
                "Could not load Phrases v5.mom — check that v5 is preserved in xcdatamodeld"
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
        throw NSError(domain: "PhrasesV6MigrationTests", code: -1)
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
