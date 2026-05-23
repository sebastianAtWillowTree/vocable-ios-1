//
//  PhraseRecordingEditorViewModelTests.swift
//  VocableTests
//

import XCTest
import CoreData
@testable import Vocable

final class PhraseRecordingEditorViewModelTests: XCTestCase {

    private var temporaryDirectory: URL!
    private var store: AudioAssetStore!
    private var context: NSManagedObjectContext!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("PhraseRecordingEditorViewModelTests")
            .appendingPathComponent(UUID().uuidString)
        store = try AudioAssetStore(baseDirectory: temporaryDirectory)
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

    func test_mode_isEmpty_whenPhraseHasNoAudioAssetID() throws {
        let phrase = makePhrase()
        try context.save()
        let vm = PhraseRecordingEditorViewModel(
            phraseID: phrase.objectID, context: context, store: store
        )
        XCTAssertEqual(vm.mode, .empty)
    }

    func test_mode_isFilled_whenPhraseHasAudioAssetID() throws {
        let phrase = makePhrase()
        phrase.setValue("audio-1", forKey: "audioAssetID")
        try context.save()
        let vm = PhraseRecordingEditorViewModel(
            phraseID: phrase.objectID, context: context, store: store
        )
        XCTAssertEqual(vm.mode, .filled(assetID: "audio-1"))
    }

    func test_requestAddOrChange_invokesDelegate() throws {
        let phrase = makePhrase()
        try context.save()
        let spy = DelegateSpy()
        let vm = PhraseRecordingEditorViewModel(
            phraseID: phrase.objectID, context: context, store: store, delegate: spy
        )
        vm.requestAddOrChange()
        XCTAssertEqual(spy.addOrChangeCalls, [phrase.objectID])
    }

    func test_requestRemove_invokesDelegate_butDoesNotMutateBeforeConfirm() throws {
        let phrase = makePhrase()
        phrase.setValue("audio-1", forKey: "audioAssetID")
        phrase.setValue(true, forKey: "prefersRecording")
        try context.save()

        let spy = DelegateSpy()
        let vm = PhraseRecordingEditorViewModel(
            phraseID: phrase.objectID, context: context, store: store, delegate: spy
        )
        vm.requestRemove()
        XCTAssertEqual(spy.removalCalls.map(\.0), [phrase.objectID])
        XCTAssertEqual(vm.mode, .filled(assetID: "audio-1"))
        XCTAssertEqual(phrase.value(forKey: "prefersRecording") as? Bool, true)
    }

    func test_confirmRemove_clearsAudioAssetID_andResetsPrefersRecording() throws {
        let phrase = makePhrase()
        phrase.setValue("audio-1", forKey: "audioAssetID")
        phrase.setValue(true, forKey: "prefersRecording")
        try context.save()

        let spy = DelegateSpy()
        let vm = PhraseRecordingEditorViewModel(
            phraseID: phrase.objectID, context: context, store: store, delegate: spy
        )
        vm.requestRemove()
        spy.removalCalls[0].1()

        XCTAssertEqual(vm.mode, .empty)
        XCTAssertNil(phrase.value(forKey: "audioAssetID"))
        XCTAssertEqual(phrase.value(forKey: "prefersRecording") as? Bool, false,
                       "Removing the recording must clear prefersRecording so playback falls back to TTS")
        XCTAssertFalse(context.hasChanges)
    }

    // MARK: - Helpers

    private final class DelegateSpy: PhraseRecordingEditorDelegate {
        var addOrChangeCalls: [NSManagedObjectID] = []
        var removalCalls: [(NSManagedObjectID, () -> Void)] = []

        func phraseRecordingEditor(
            _ editor: PhraseRecordingEditorViewModel,
            requestsAddOrChangeRecordingFor phraseID: NSManagedObjectID
        ) {
            addOrChangeCalls.append(phraseID)
        }

        func phraseRecordingEditor(
            _ editor: PhraseRecordingEditorViewModel,
            requestsRemovalConfirmationFor phraseID: NSManagedObjectID,
            confirm: @escaping () -> Void
        ) {
            removalCalls.append((phraseID, confirm))
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
        throw NSError(domain: "PhraseRecordingEditorViewModelTests", code: -1)
    }

    @discardableResult
    private func makePhrase() -> NSManagedObject {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("cat-1", forKey: "identifier")
        category.setValue("Drinks", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context)
        phrase.setValue("p1", forKey: "identifier")
        phrase.setValue("hello", forKey: "utterance")
        phrase.setValue(Date(), forKey: "creationDate")
        phrase.setValue(category, forKey: "category")
        return phrase
    }
}
