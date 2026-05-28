//
//  PhraseSoftDeleteTests.swift
//  VocableTests
//

import XCTest
import CoreData
@testable import Vocable

final class PhraseSoftDeleteTests: XCTestCase {

    private var container: NSPersistentContainer!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let momdURL = try locateMomdURL()
        let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: momdURL))
        container = NSPersistentContainer(name: "Phrases", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        context = container.viewContext
    }

    override func tearDownWithError() throws {
        context = nil
        container = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_softDelete_setsIsUserRemoved_andClearsAssetIDs() throws {
        let phrase = makePhrase()
        phrase.imageAssetID = "img-asset"
        phrase.audioAssetID = "audio-asset"
        phrase.prefersRecording = true
        try context.save()

        phrase.softDelete()

        XCTAssertTrue(phrase.isUserRemoved)
        XCTAssertNil(phrase.imageAssetID,
                     "Soft-delete must clear imageAssetID so the file can be reclaimed")
        XCTAssertNil(phrase.audioAssetID,
                     "Soft-delete must clear audioAssetID so the file can be reclaimed")
        XCTAssertFalse(phrase.prefersRecording,
                       "Soft-delete must clear prefersRecording since no recording remains")
    }

    func test_softDelete_isIdempotent_onAlreadyClearedPhrase() throws {
        let phrase = makePhrase()
        try context.save()

        phrase.softDelete()
        phrase.softDelete()

        XCTAssertTrue(phrase.isUserRemoved)
        XCTAssertNil(phrase.imageAssetID)
        XCTAssertNil(phrase.audioAssetID)
    }

    func test_softDelete_doesNotMutateUtterance_orIdentity() throws {
        let phrase = makePhrase()
        phrase.utterance = "hello"
        phrase.imageAssetID = "img-1"
        try context.save()

        phrase.softDelete()

        XCTAssertEqual(phrase.utterance, "hello", "Utterance should survive soft-delete (still findable in recents/history)")
        XCTAssertEqual(phrase.identifier, "p1", "Identifier is stable across soft-delete")
    }

    // MARK: - Helpers

    private func locateMomdURL() throws -> URL {
        if let url = Bundle.main.url(forResource: "Phrases", withExtension: "momd") { return url }
        for bundle in Bundle.allBundles {
            if let url = bundle.url(forResource: "Phrases", withExtension: "momd") { return url }
        }
        for bundle in Bundle.allFrameworks {
            if let url = bundle.url(forResource: "Phrases", withExtension: "momd") { return url }
        }
        XCTFail("Could not locate Phrases.momd")
        throw NSError(domain: "PhraseSoftDeleteTests", code: -1)
    }

    private func makePhrase() -> Phrase {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("cat-1", forKey: "identifier")
        category.setValue("Test", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context) as! Phrase
        phrase.identifier = "p1"
        phrase.utterance = "hi"
        phrase.creationDate = Date()
        phrase.setValue(category, forKey: "category")
        return phrase
    }
}
