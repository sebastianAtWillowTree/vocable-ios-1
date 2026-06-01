//
//  CartoonStylePromptAugmenterTests.swift
//  VocableTests
//

import XCTest
@testable import Vocable

final class CartoonStylePromptAugmenterTests: XCTestCase {

    func test_augment_appendsHint_toRegularPrompt() {
        XCTAssertEqual(
            CartoonStylePromptAugmenter.augment("a red ball"),
            "a red ball, high contrast"
        )
    }

    func test_augment_trimsLeadingAndTrailingWhitespace() {
        XCTAssertEqual(
            CartoonStylePromptAugmenter.augment("  a blue cup  "),
            "a blue cup, high contrast"
        )
    }

    func test_augment_emptyPrompt_returnsEmpty() {
        XCTAssertEqual(CartoonStylePromptAugmenter.augment(""), "")
    }

    func test_augment_whitespacePrompt_returnsEmpty() {
        XCTAssertEqual(CartoonStylePromptAugmenter.augment("   \n\t  "), "")
    }

    func test_augment_isIdempotent_whenPromptAlreadyHasHint() {
        // Caregiver explicitly mentioned high contrast — don't duplicate.
        XCTAssertEqual(
            CartoonStylePromptAugmenter.augment("a red ball, high contrast"),
            "a red ball, high contrast"
        )
    }

    func test_augment_isIdempotent_caseInsensitive() {
        XCTAssertEqual(
            CartoonStylePromptAugmenter.augment("A red ball with HIGH CONTRAST colors"),
            "A red ball with HIGH CONTRAST colors"
        )
    }

    func test_augment_matchesHintAsSubstring() {
        // "ultra-high contrast" already conveys the hint — treat as present.
        XCTAssertEqual(
            CartoonStylePromptAugmenter.augment("an ultra-high contrast painting"),
            "an ultra-high contrast painting"
        )
    }
}
