//
//  PhrasePhotoEditorViewModelTests.swift
//  VocableTests
//

import XCTest
import CoreData
import UIKit
@testable import Vocable

final class PhrasePhotoEditorViewModelTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var store: ImageAssetStore!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhrasePhotoEditorViewModelTests")
            .appendingPathComponent(UUID().uuidString)
        store = try ImageAssetStore(baseDirectory: temporaryDirectory)
        context = try makeInMemoryContext()
    }

    override func tearDownWithError() throws {
        context = nil
        store = nil
        if let temporaryDirectory {
            try? FileManager.default.removeItem(at: temporaryDirectory)
        }
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_mode_isEmpty_whenPhraseHasNoImageAssetID() throws {
        let phrase = makePhraseWithCategory()
        try context.save()

        let viewModel = PhrasePhotoEditorViewModel(
            phraseID: phrase.objectID,
            context: context,
            store: store
        )

        XCTAssertEqual(viewModel.mode, .empty)
    }

    func test_mode_isFilled_whenPhraseHasImageAssetID() throws {
        let phrase = makePhraseWithCategory()
        phrase.setValue("asset-123", forKey: "imageAssetID")
        try context.save()

        let viewModel = PhrasePhotoEditorViewModel(
            phraseID: phrase.objectID,
            context: context,
            store: store
        )

        XCTAssertEqual(viewModel.mode, .filled(assetID: "asset-123"))
    }

    func test_requestAddOrChange_invokesDelegateWithPhraseID() throws {
        let phrase = makePhraseWithCategory()
        try context.save()

        let spy = DelegateSpy()
        let viewModel = PhrasePhotoEditorViewModel(
            phraseID: phrase.objectID,
            context: context,
            store: store,
            delegate: spy
        )

        viewModel.requestAddOrChange()

        XCTAssertEqual(spy.addOrChangeCalls, [phrase.objectID])
        XCTAssertTrue(spy.removalConfirmCalls.isEmpty)
    }

    func test_requestRemove_invokesDelegateForConfirmation() throws {
        let phrase = makePhraseWithCategory()
        phrase.setValue("asset-456", forKey: "imageAssetID")
        try context.save()

        let spy = DelegateSpy()
        let viewModel = PhrasePhotoEditorViewModel(
            phraseID: phrase.objectID,
            context: context,
            store: store,
            delegate: spy
        )

        viewModel.requestRemove()

        XCTAssertEqual(spy.removalConfirmCalls.map(\.0), [phrase.objectID])
        XCTAssertEqual(viewModel.mode, .filled(assetID: "asset-456"),
                       "Mode should not change until confirmation fires")
    }

    func test_confirmRemove_clearsImageAssetID_andSavesContext() throws {
        let phrase = makePhraseWithCategory()
        phrase.setValue("asset-456", forKey: "imageAssetID")
        try context.save()

        let spy = DelegateSpy()
        let viewModel = PhrasePhotoEditorViewModel(
            phraseID: phrase.objectID,
            context: context,
            store: store,
            delegate: spy
        )

        viewModel.requestRemove()
        XCTAssertEqual(spy.removalConfirmCalls.count, 1)
        spy.removalConfirmCalls[0].1()    // invoke the confirm closure

        XCTAssertEqual(viewModel.mode, .empty)
        XCTAssertNil(phrase.value(forKey: "imageAssetID"))
        XCTAssertFalse(context.hasChanges, "Removal should be persisted")
    }

    // MARK: - Helpers

    private final class DelegateSpy: PhrasePhotoEditorDelegate {
        var addOrChangeCalls: [NSManagedObjectID] = []
        var removalConfirmCalls: [(NSManagedObjectID, () -> Void)] = []

        func phrasePhotoEditor(
            _ editor: PhrasePhotoEditorViewModel,
            requestsAddOrChangePhotoFor phraseID: NSManagedObjectID
        ) {
            addOrChangeCalls.append(phraseID)
        }

        func phrasePhotoEditor(
            _ editor: PhrasePhotoEditorViewModel,
            requestsRemovalConfirmationFor phraseID: NSManagedObjectID,
            confirm: @escaping () -> Void
        ) {
            removalConfirmCalls.append((phraseID, confirm))
        }
    }

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
        throw NSError(domain: "PhrasePhotoEditorViewModelTests", code: -1)
    }

    private func makePhraseWithCategory() -> NSManagedObject {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("test-cat", forKey: "identifier")
        category.setValue("TestCat", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        phrase.setValue("test-phrase", forKey: "identifier")
        phrase.setValue("hello", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue(category, forKey: "category")
        return phrase
    }
}
