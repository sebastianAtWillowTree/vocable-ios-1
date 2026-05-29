//
//  VisionNLPAlignerTests.swift
//  VocableTests
//
//  Drives the alignment orchestration with stubbed seams. Production
//  Vision / NaturalLanguage code is exercised separately (or relied
//  on as Apple's contract) — these tests cover the decision logic.
//

import XCTest
import UIKit
@testable import Vocable

final class VisionNLPAlignerTests: XCTestCase {

    private var classifier: StubImageClassifier!
    private var personDetector: StubPersonDetector!
    private var tokenizer: StubPromptTokenizer!
    private var similarity: StubSimilarity!
    private var aligner: VisionNLPAligner!

    override func setUp() {
        super.setUp()
        classifier = StubImageClassifier()
        personDetector = StubPersonDetector()
        tokenizer = StubPromptTokenizer()
        similarity = StubSimilarity()
        aligner = VisionNLPAligner(
            classifier: classifier,
            personDetector: personDetector,
            tokenizer: tokenizer,
            similarity: similarity
        )
    }

    // MARK: - Insufficient signal

    func test_emptyPrompt_returnsUnknownInsufficientSignal() {
        tokenizer.nouns = []
        personDetector.contains = false
        classifier.labels = []

        let result = run(prompt: "")
        XCTAssertEqual(result, .unknownInsufficientSignal)
    }

    func test_noClassifierLabels_andNoPerson_returnsUnknownInsufficientSignal() {
        tokenizer.nouns = ["car"]
        personDetector.contains = false
        classifier.labels = []

        let result = run(prompt: "a red car")
        XCTAssertEqual(result, .unknownInsufficientSignal)
    }

    func test_classifierLabelsBelowConfidenceFloor_areIgnored() {
        // Only low-confidence labels → effectively no signal → unknown.
        tokenizer.nouns = ["car"]
        personDetector.contains = false
        classifier.labels = [
            ImageClassificationLabel(identifier: "sports_car", confidence: 0.05),
            ImageClassificationLabel(identifier: "minivan", confidence: 0.02)
        ]
        let result = run(prompt: "a red car")
        XCTAssertEqual(result, .unknownInsufficientSignal)
    }

    // MARK: - Aligned via direct head-noun match

    func test_directHeadNounMatch_returnsAligned() {
        tokenizer.nouns = ["car"]
        personDetector.contains = false
        classifier.labels = [
            ImageClassificationLabel(identifier: "sports_car", confidence: 0.82)
        ]
        // No need for embedding — head-noun "car" matches prompt "car".
        let result = run(prompt: "a red sports car")
        XCTAssertEqual(result, .aligned)
    }

    // MARK: - Aligned via semantic similarity

    func test_embeddingSimilarityAboveThreshold_returnsAligned() {
        tokenizer.nouns = ["cup"]
        personDetector.contains = false
        classifier.labels = [
            ImageClassificationLabel(identifier: "drinking_glass", confidence: 0.71)
        ]
        // "cup" vs "glass" — assume embedding says they're close.
        similarity.fixed = ["cup|glass": 0.62]

        let result = run(prompt: "a sippy cup")
        XCTAssertEqual(result, .aligned)
    }

    func test_embeddingSimilarityBelowThreshold_isNotAligned() {
        tokenizer.nouns = ["ball"]
        personDetector.contains = false
        classifier.labels = [
            ImageClassificationLabel(identifier: "laptop_computer", confidence: 0.55)
        ]
        similarity.fixed = ["ball|computer": 0.18]

        let result = run(prompt: "a blue ball")
        if case .misaligned(.noOverlapBetweenPromptAndImage(let nouns, let heads)) = result {
            XCTAssertEqual(nouns, ["ball"])
            XCTAssertEqual(heads, ["computer"])
        } else {
            XCTFail("Expected .misaligned(.noOverlapBetweenPromptAndImage), got \(result)")
        }
    }

    // MARK: - Person-special-case

    func test_personDetected_withObjectPrompt_returnsPersonMisalignment() {
        tokenizer.nouns = ["cup"]
        personDetector.contains = true
        classifier.labels = [
            ImageClassificationLabel(identifier: "drinking_glass", confidence: 0.71)
        ]
        // Even though embedding may say cup~glass, the person detection
        // wins — the lifted subject is a person, the prompt is about an
        // object; surfaced as the high-signal personhood mismatch.
        similarity.fixed = ["cup|glass": 0.62]

        let result = run(prompt: "a sippy cup")
        if case .misaligned(.personSubjectButPromptIsObject(let nouns)) = result {
            XCTAssertEqual(nouns, ["cup"])
        } else {
            XCTFail("Expected .misaligned(.personSubjectButPromptIsObject), got \(result)")
        }
    }

    func test_personDetected_withPersonPrompt_returnsAligned() {
        // "mom" is in PersonhoodVocabulary.lemmas — alignment passes
        // immediately on the personhood check, no embedding needed.
        tokenizer.nouns = ["mom"]
        personDetector.contains = true
        classifier.labels = [
            ImageClassificationLabel(identifier: "person", confidence: 0.93)
        ]
        let result = run(prompt: "Mom")
        XCTAssertEqual(result, .aligned)
    }

    func test_personDetected_withPersonPrompt_caseInsensitive() {
        // Tokenizer is responsible for lowercasing; this test makes that
        // contract explicit.
        tokenizer.nouns = ["kid"]
        personDetector.contains = true
        classifier.labels = [
            ImageClassificationLabel(identifier: "person", confidence: 0.93)
        ]
        let result = run(prompt: "My Kid")
        XCTAssertEqual(result, .aligned)
    }

    func test_personDetected_noPromptNouns_returnsUnknownInsufficientSignal() {
        // Person detected but prompt yielded no nouns — we can't even
        // check personhood. Don't raise a false warning.
        tokenizer.nouns = []
        personDetector.contains = true
        classifier.labels = [
            ImageClassificationLabel(identifier: "person", confidence: 0.93)
        ]
        let result = run(prompt: "!!!")
        XCTAssertEqual(result, .unknownInsufficientSignal)
    }

    // MARK: - No-overlap path payload contents

    func test_noOverlap_misalignment_includesTopLabelsAsImageHeadNouns() {
        tokenizer.nouns = ["ball"]
        personDetector.contains = false
        classifier.labels = [
            ImageClassificationLabel(identifier: "sports_car", confidence: 0.80),
            ImageClassificationLabel(identifier: "minivan", confidence: 0.45),
            // Below floor — excluded.
            ImageClassificationLabel(identifier: "bicycle", confidence: 0.03)
        ]
        similarity.fixed = [
            "ball|car": 0.05,
            "ball|minivan": 0.04
        ]
        let result = run(prompt: "a ball")
        if case .misaligned(.noOverlapBetweenPromptAndImage(let nouns, let heads)) = result {
            XCTAssertEqual(nouns, ["ball"])
            // Head nouns are the last underscore segment of each label.
            XCTAssertEqual(Set(heads), Set(["car", "minivan"]))
        } else {
            XCTFail("Expected .misaligned(.noOverlapBetweenPromptAndImage), got \(result)")
        }
    }

    // MARK: - Helpers

    private func run(prompt: String) -> AlignmentResult {
        var captured: AlignmentResult?
        let exp = expectation(description: "align completes")
        aligner.align(image: makeImage(), prompt: prompt) { result in
            captured = result
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        return captured ?? .unknownInsufficientSignal
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 8, height: 8), format: format)
        return renderer.image { ctx in
            UIColor.gray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        }
    }
}

// MARK: - Test doubles

private final class StubImageClassifier: ImageClassifying {
    var labels: [ImageClassificationLabel] = []
    func classify(image: UIImage, completion: @escaping ([ImageClassificationLabel]) -> Void) {
        completion(labels)
    }
}

private final class StubPersonDetector: PersonInImageDetecting {
    var contains = false
    func containsPerson(image: UIImage, completion: @escaping (Bool) -> Void) {
        completion(contains)
    }
}

private final class StubPromptTokenizer: PromptTokenizing {
    var nouns: [String] = []
    func extractNouns(from prompt: String) -> [String] { nouns }
}

private final class StubSimilarity: SemanticSimilarityProviding {
    /// Keyed by "a|b" with a and b sorted alphabetically.
    var fixed: [String: Float] = [:]
    func similarity(between a: String, and b: String) -> Float? {
        let key = [a.lowercased(), b.lowercased()].sorted().joined(separator: "|")
        return fixed[key]
    }
}
