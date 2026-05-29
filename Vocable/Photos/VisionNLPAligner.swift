//
//  VisionNLPAligner.swift
//  Vocable
//
//  Production PromptSubjectAligning. Composes four seam protocols so
//  the orchestration logic is unit-testable without invoking Vision
//  or NaturalLanguage at test time. The seam adapters in this file
//  are the only real-framework code.
//
//  Decision logic (in order):
//      1. No prompt nouns                 → unknownInsufficientSignal
//      2. Person detected in image
//         a. Prompt has person word       → aligned
//         b. Prompt has only object words → misaligned(.personSubjectButPromptIsObject)
//      3. No usable image labels          → unknownInsufficientSignal
//      4. Prompt noun == label head noun  → aligned
//      5. Semantic similarity ≥ threshold → aligned
//      6. Otherwise                       → misaligned(.noOverlapBetweenPromptAndImage)
//

import UIKit
import Vision
import NaturalLanguage

// MARK: - Aligner

final class VisionNLPAligner: PromptSubjectAligning {

    /// Vision confidence floor. Labels weaker than this are not
    /// considered "signal" and don't contribute to the comparison.
    static let labelConfidenceFloor: Float = 0.10

    /// Cosine threshold above which two tokens are considered a
    /// semantic match. Empirically chosen — high enough to avoid
    /// "ball ↔ computer" false positives, low enough to keep
    /// "cup ↔ glass" together.
    static let similarityThreshold: Float = 0.55

    private let classifier: ImageClassifying
    private let personDetector: PersonInImageDetecting
    private let tokenizer: PromptTokenizing
    private let similarity: SemanticSimilarityProviding

    init(
        classifier: ImageClassifying,
        personDetector: PersonInImageDetecting,
        tokenizer: PromptTokenizing,
        similarity: SemanticSimilarityProviding
    ) {
        self.classifier = classifier
        self.personDetector = personDetector
        self.tokenizer = tokenizer
        self.similarity = similarity
    }

    func align(
        image: UIImage,
        prompt: String,
        completion: @escaping (AlignmentResult) -> Void
    ) {
        let nouns = tokenizer.extractNouns(from: prompt)
        guard !nouns.isEmpty else {
            completion(.unknownInsufficientSignal)
            return
        }

        personDetector.containsPerson(image: image) { [classifier, similarity] hasPerson in
            classifier.classify(image: image) { rawLabels in
                let usable = rawLabels.filter { $0.confidence >= Self.labelConfidenceFloor }
                let headNouns = Self.headNouns(from: usable)

                // Personhood is high-signal and overrides label matching.
                if hasPerson {
                    if nouns.contains(where: { PersonhoodVocabulary.lemmas.contains($0) }) {
                        completion(.aligned)
                    } else {
                        completion(.misaligned(reason: .personSubjectButPromptIsObject(promptNouns: nouns)))
                    }
                    return
                }

                guard !headNouns.isEmpty else {
                    completion(.unknownInsufficientSignal)
                    return
                }

                // Direct head-noun match.
                let headSet = Set(headNouns)
                if nouns.contains(where: { headSet.contains($0) }) {
                    completion(.aligned)
                    return
                }

                // Semantic neighbourhood (e.g. cup ↔ glass).
                for noun in nouns {
                    for head in headNouns {
                        if let sim = similarity.similarity(between: noun, and: head),
                           sim >= Self.similarityThreshold {
                            completion(.aligned)
                            return
                        }
                    }
                }

                completion(.misaligned(reason: .noOverlapBetweenPromptAndImage(
                    promptNouns: nouns,
                    imageLabelHeadNouns: headNouns
                )))
            }
        }
    }

    /// Vision returns ImageNet-style identifiers like "drinking_glass"
    /// or "golden_retriever". The head noun (last underscore segment)
    /// is the most useful comparison token in English. Order preserved
    /// from `usable`, with duplicates dropped.
    private static func headNouns(from labels: [ImageClassificationLabel]) -> [String] {
        var seen: Set<String> = []
        var result: [String] = []
        for label in labels {
            let head = label.identifier.split(separator: "_").last.map(String.init) ?? label.identifier
            let lower = head.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                result.append(lower)
            }
        }
        return result
    }
}

// MARK: - Vision classifier adapter

final class VisionImageClassifier: ImageClassifying {

    func classify(
        image: UIImage,
        completion: @escaping ([ImageClassificationLabel]) -> Void
    ) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async { completion([]) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let request = VNClassifyImageRequest()
            do {
                try handler.perform([request])
                let observations = (request.results ?? [])
                    .prefix(8) // Top-8 — anything below is rarely useful.
                    .map { obs in
                        ImageClassificationLabel(
                            identifier: obs.identifier,
                            confidence: obs.confidence
                        )
                    }
                DispatchQueue.main.async { completion(Array(observations)) }
            } catch {
                DispatchQueue.main.async { completion([]) }
            }
        }
    }
}

// MARK: - Person detector adapter

final class VisionPersonDetector: PersonInImageDetecting {

    func containsPerson(
        image: UIImage,
        completion: @escaping (Bool) -> Void
    ) {
        guard let cgImage = image.cgImage else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        DispatchQueue.global(qos: .userInitiated).async {
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            let humanRequest = VNDetectHumanRectanglesRequest()
            let faceRequest = VNDetectFaceRectanglesRequest()
            var found = false
            do {
                try handler.perform([humanRequest, faceRequest])
                if !(humanRequest.results?.isEmpty ?? true) { found = true }
                if !(faceRequest.results?.isEmpty ?? true) { found = true }
            } catch {
                // If Vision errored, don't claim a person exists — we'd
                // surface a false misalignment warning. Better to fall
                // through to the label-based path.
                found = false
            }
            DispatchQueue.main.async { completion(found) }
        }
    }
}

// MARK: - Prompt tokenizer adapter

final class NLPromptTokenizer: PromptTokenizing {

    func extractNouns(from prompt: String) -> [String] {
        let trimmed = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        let tagger = NLTagger(tagSchemes: [.lexicalClass, .lemma])
        tagger.string = trimmed
        let options: NLTagger.Options = [.omitPunctuation, .omitWhitespace, .joinNames]
        let range = trimmed.startIndex..<trimmed.endIndex

        var seen: Set<String> = []
        var nouns: [String] = []

        tagger.enumerateTags(
            in: range,
            unit: .word,
            scheme: .lexicalClass,
            options: options
        ) { tag, tokenRange in
            guard tag == .noun else { return true }
            // Prefer the lemma; fall back to the surface form lowercased.
            let lemmaTag = tagger.tag(
                at: tokenRange.lowerBound,
                unit: .word,
                scheme: .lemma
            ).0
            let token: String = lemmaTag?.rawValue ?? String(trimmed[tokenRange])
            let lower = token.lowercased()
            if !seen.contains(lower) {
                seen.insert(lower)
                nouns.append(lower)
            }
            return true
        }
        return nouns
    }
}

// MARK: - Similarity adapter

final class NLSemanticSimilarity: SemanticSimilarityProviding {

    /// Lazily resolved; nil on simulators / locales where the embedding
    /// model isn't installed. The aligner treats nil as "no opinion"
    /// and falls back to direct matching.
    private lazy var embedding: NLEmbedding? = NLEmbedding.wordEmbedding(for: .english)

    func similarity(between a: String, and b: String) -> Float? {
        guard let embedding else { return nil }
        let lowerA = a.lowercased()
        let lowerB = b.lowercased()
        guard embedding.contains(lowerA), embedding.contains(lowerB) else { return nil }
        // NLEmbedding.distance returns 0 for identical, larger for
        // dissimilar. Convert to a 0…1 "similarity" via 1 - distance,
        // clamped. Cosine distance is in [0, 2] for unit vectors so we
        // do a clamp + linear map. Empirically good enough for the
        // gross "cup ↔ glass" / "ball ↔ computer" distinctions; not
        // intended to be a calibrated similarity score.
        let distance = Float(embedding.distance(between: lowerA, and: lowerB, distanceType: .cosine))
        let raw = 1.0 - distance
        return max(-1.0, min(1.0, raw))
    }
}
