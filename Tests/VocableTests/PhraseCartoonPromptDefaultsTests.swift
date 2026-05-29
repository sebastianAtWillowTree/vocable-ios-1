//
//  PhraseCartoonPromptDefaultsTests.swift
//  VocableTests
//

import XCTest
import CoreData
@testable import Vocable

final class PhraseCartoonPromptDefaultsTests: XCTestCase {

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

    func test_initialCartoonPrompt_prefersSavedCartoonPrompt() {
        let phrase = makePhrase(utterance: "cup", cartoonPrompt: "a blue sippy cup with handles")
        XCTAssertEqual(phrase.initialCartoonPrompt, "a blue sippy cup with handles")
    }

    func test_initialCartoonPrompt_fallsBackToUtteranceTemplate_whenNoSavedPrompt() {
        let phrase = makePhrase(utterance: "cup", cartoonPrompt: nil)
        let result = phrase.initialCartoonPrompt
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("cup") ?? false,
                      "Default should include the utterance, got: \(result ?? "nil")")
    }

    func test_initialCartoonPrompt_treatsWhitespaceOnlySavedPromptAsEmpty() {
        let phrase = makePhrase(utterance: "cup", cartoonPrompt: "   \n\t   ")
        let result = phrase.initialCartoonPrompt
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("cup") ?? false,
                      "Whitespace-only saved prompt should fall through to utterance template")
    }

    func test_initialCartoonPrompt_trimsUtteranceWhitespace() {
        let phrase = makePhrase(utterance: "  cup  ", cartoonPrompt: nil)
        let result = phrase.initialCartoonPrompt
        XCTAssertNotNil(result)
        XCTAssertTrue(result?.contains("cup") ?? false)
        XCTAssertFalse(result?.contains("  cup  ") ?? true,
                       "Template should not contain leading/trailing whitespace from the utterance")
    }

    func test_initialCartoonPrompt_returnsNil_whenNoUtteranceAndNoSavedPrompt() {
        let phrase = makePhrase(utterance: nil, cartoonPrompt: nil)
        XCTAssertNil(phrase.initialCartoonPrompt)
    }

    func test_initialCartoonPrompt_returnsNil_whenUtteranceIsWhitespaceOnly() {
        let phrase = makePhrase(utterance: "   ", cartoonPrompt: nil)
        XCTAssertNil(phrase.initialCartoonPrompt)
    }

    func test_initialCartoonPrompt_returnsNil_whenUtteranceEmpty_AndPromptEmpty() {
        let phrase = makePhrase(utterance: "", cartoonPrompt: "")
        XCTAssertNil(phrase.initialCartoonPrompt)
    }

    func test_initialCartoonPrompt_savedPromptUsedVerbatim_includingMultiWord() {
        let phrase = makePhrase(
            utterance: "cup",
            cartoonPrompt: "a happy yellow cup with a red striped pattern"
        )
        XCTAssertEqual(phrase.initialCartoonPrompt,
                       "a happy yellow cup with a red striped pattern")
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
        throw NSError(domain: "PhraseCartoonPromptDefaultsTests", code: -1)
    }

    private func makePhrase(utterance: String?, cartoonPrompt: String?) -> Phrase {
        let category = NSEntityDescription.insertNewObject(forEntityName: "Category", into: context)
        category.setValue("cat-1", forKey: "identifier")
        category.setValue("Test", forKey: "name")
        category.setValue(Date(), forKey: "creationDate")

        let phrase = NSEntityDescription.insertNewObject(forEntityName: "Phrase", into: context) as! Phrase
        phrase.identifier = "p1"
        phrase.utterance = utterance
        phrase.cartoonPrompt = cartoonPrompt
        phrase.creationDate = Date()
        phrase.setValue(category, forKey: "category")
        return phrase
    }
}
