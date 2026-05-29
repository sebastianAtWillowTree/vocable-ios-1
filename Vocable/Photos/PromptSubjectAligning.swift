//
//  PromptSubjectAligning.swift
//  Vocable
//
//  Cross-checks a caregiver's free-form cartoon description against
//  the actual content of a subject-lifted image, BEFORE we hand off
//  to Image Playground. The failure case we're trying to catch:
//      • photo of kid holding a sippy cup
//      • subject lift extracts the kid (bigger salient subject)
//      • caregiver typed "blue sippy cup"
//      • Image Playground gets a person-shaped mask + an object prompt
//        → garbage output, wasted on-device generation, confused user
//
//  The aligner does not enforce — it produces an AlignmentResult that
//  CartoonifyPreflightCoordinator surfaces as a soft warning. The
//  caregiver can always choose to continue anyway.
//
//  All four underlying signals (image classification, person
//  detection, noun extraction, semantic similarity) are seamed as
//  protocols so unit tests can drive the orchestration without
//  touching Vision/NaturalLanguage at runtime.
//

import UIKit

// MARK: - Public protocol + result

protocol PromptSubjectAligning: AnyObject {
    /// Asynchronously decides whether the caregiver's prompt seems to
    /// describe what's actually in the lifted image. Completion fires
    /// on the main queue.
    func align(
        image: UIImage,
        prompt: String,
        completion: @escaping (AlignmentResult) -> Void
    )
}

enum AlignmentResult: Equatable {
    case aligned
    case misaligned(reason: AlignmentMismatchReason)
    /// We don't have enough signal to make a call — empty prompt,
    /// classifier returned nothing, or the embedding is unavailable
    /// for this locale. Treated as "proceed without warning" by the
    /// preflight UI so we don't punish caregivers for our flakiness.
    case unknownInsufficientSignal
}

enum AlignmentMismatchReason: Equatable {
    /// Vision detected a human/face in the lifted subject, but the
    /// prompt's nouns don't include any person-like word
    /// ("kid", "mom", "person", …). High-signal mismatch — cartoonify
    /// will model the wrong thing.
    case personSubjectButPromptIsObject(promptNouns: [String])

    /// Neither the prompt nouns nor their semantic neighbours
    /// overlapped with the top image labels. Lower-signal but still
    /// worth surfacing.
    case noOverlapBetweenPromptAndImage(
        promptNouns: [String],
        imageLabelHeadNouns: [String]
    )
}

// MARK: - Seam protocols (one underlying signal each)

/// Top-N labels for an image, sorted by confidence descending.
struct ImageClassificationLabel: Equatable {
    /// ImageNet-style identifier with underscores, e.g. "drinking_glass",
    /// "golden_retriever". The aligner extracts the head noun for
    /// matching.
    let identifier: String
    /// Vision confidence in 0…1.
    let confidence: Float
}

protocol ImageClassifying: AnyObject {
    func classify(
        image: UIImage,
        completion: @escaping ([ImageClassificationLabel]) -> Void
    )
}

protocol PersonInImageDetecting: AnyObject {
    /// True when at least one human body or face rectangle is detected
    /// inside the image.
    func containsPerson(
        image: UIImage,
        completion: @escaping (Bool) -> Void
    )
}

protocol PromptTokenizing: AnyObject {
    /// Returns lowercased lemmatized nouns from a free-form prompt.
    /// Empty if no nouns were found.
    func extractNouns(from prompt: String) -> [String]
}

protocol SemanticSimilarityProviding: AnyObject {
    /// Cosine similarity in [-1, 1]. Returns nil when the embedding
    /// can't score the pair (unknown token, model unavailable). Callers
    /// should treat nil as "no opinion", not "definitely different".
    func similarity(between a: String, and b: String) -> Float?
}

// MARK: - Shared vocabulary

enum PersonhoodVocabulary {
    /// Lowercased lemmas. Conservative — meant to catch common AAC
    /// caregiver vocabulary, not to be a comprehensive personhood
    /// classifier. Anything we miss just degrades to the "no overlap"
    /// path, which is also a soft warning.
    static let lemmas: Set<String> = [
        "person", "people", "human", "face",
        "kid", "child", "baby", "toddler",
        "boy", "girl", "guy", "lady", "man", "woman",
        "mom", "mommy", "mum", "mummy", "mother",
        "dad", "daddy", "father",
        "grandma", "granny", "grandmother",
        "grandpa", "grandfather", "grandparent",
        "uncle", "aunt", "auntie",
        "brother", "sister", "sibling", "cousin",
        "friend", "teacher", "nurse", "doctor",
        "me", "you", "us"
    ]
}
