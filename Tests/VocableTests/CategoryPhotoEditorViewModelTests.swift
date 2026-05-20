//
//  CategoryPhotoEditorViewModelTests.swift
//  VocableTests
//

import XCTest
import CoreData
import UIKit
@testable import Vocable

final class CategoryPhotoEditorViewModelTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var store: ImageAssetStore!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CategoryPhotoEditorViewModelTests")
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

    func test_mode_isEmpty_whenCategoryHasNoImageAssetID() throws {
        let category = makeCategory()
        try context.save()
        let vm = CategoryPhotoEditorViewModel(categoryID: category.objectID, context: context, store: store)
        XCTAssertEqual(vm.mode, .empty)
    }

    func test_mode_isFilled_whenCategoryHasImageAssetID() throws {
        let category = makeCategory()
        category.setValue("asset-cat-1", forKey: "imageAssetID")
        try context.save()
        let vm = CategoryPhotoEditorViewModel(categoryID: category.objectID, context: context, store: store)
        XCTAssertEqual(vm.mode, .filled(assetID: "asset-cat-1"))
    }

    func test_requestAddOrChange_invokesDelegateWithCategoryID() throws {
        let category = makeCategory()
        try context.save()
        let spy = DelegateSpy()
        let vm = CategoryPhotoEditorViewModel(
            categoryID: category.objectID, context: context, store: store, delegate: spy
        )
        vm.requestAddOrChange()
        XCTAssertEqual(spy.addOrChangeCalls, [category.objectID])
    }

    func test_requestRemove_invokesDelegateForConfirmation_andDoesNotMutateUntilConfirmed() throws {
        let category = makeCategory()
        category.setValue("asset-cat-2", forKey: "imageAssetID")
        try context.save()
        let spy = DelegateSpy()
        let vm = CategoryPhotoEditorViewModel(
            categoryID: category.objectID, context: context, store: store, delegate: spy
        )
        vm.requestRemove()
        XCTAssertEqual(spy.removalCalls.map(\.0), [category.objectID])
        XCTAssertEqual(vm.mode, .filled(assetID: "asset-cat-2"))
    }

    func test_confirmRemove_clearsImageAssetID_andSavesContext() throws {
        let category = makeCategory()
        category.setValue("asset-cat-3", forKey: "imageAssetID")
        try context.save()
        let spy = DelegateSpy()
        let vm = CategoryPhotoEditorViewModel(
            categoryID: category.objectID, context: context, store: store, delegate: spy
        )
        vm.requestRemove()
        spy.removalCalls[0].1()

        XCTAssertEqual(vm.mode, .empty)
        XCTAssertNil(category.value(forKey: "imageAssetID"))
        XCTAssertFalse(context.hasChanges)
    }

    // MARK: - Helpers

    private final class DelegateSpy: CategoryPhotoEditorDelegate {
        var addOrChangeCalls: [NSManagedObjectID] = []
        var removalCalls: [(NSManagedObjectID, () -> Void)] = []

        func categoryPhotoEditor(
            _ editor: CategoryPhotoEditorViewModel,
            requestsAddOrChangePhotoFor categoryID: NSManagedObjectID
        ) {
            addOrChangeCalls.append(categoryID)
        }

        func categoryPhotoEditor(
            _ editor: CategoryPhotoEditorViewModel,
            requestsRemovalConfirmationFor categoryID: NSManagedObjectID,
            confirm: @escaping () -> Void
        ) {
            removalCalls.append((categoryID, confirm))
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
        throw NSError(domain: "CategoryPhotoEditorViewModelTests", code: -1)
    }

    private func makeCategory() -> NSManagedObject {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("cat-1", forKey: "identifier")
        category.setValue("Test", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")
        return category
    }
}
