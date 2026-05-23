//
//  PresetCellThumbnailTests.swift
//  VocableTests
//
//  Covers C1, C2, C4, C5 — thumbnail rendering on phrase + category
//  cells, fixed cell height across thumbnail states, and image
//  marked as a non-accessibility element.
//

import XCTest
import UIKit
@testable import Vocable

final class PresetCellThumbnailTests: XCTestCase {

    private var loader: SpyThumbnailLoader!

    override func setUpWithError() throws {
        try super.setUpWithError()
        loader = SpyThumbnailLoader()
    }

    override func tearDownWithError() throws {
        loader = nil
        try super.tearDownWithError()
    }

    // MARK: - C1: phrase cell rendering

    func test_phraseCell_withNilAssetID_hidesThumbnail() {
        let cell = makePhraseCell()
        cell.configureThumbnail(assetID: nil, loader: loader)
        XCTAssertTrue(cell.thumbnailImageView.isHidden)
        XCTAssertNil(cell.thumbnailImageView.image)
        XCTAssertEqual(loader.loadCalls.count, 0)
    }

    func test_phraseCell_withAssetID_revealsThumbnail_andRequestsLoad() {
        let cell = makePhraseCell()
        cell.configureThumbnail(assetID: "abc", loader: loader)
        XCTAssertFalse(cell.thumbnailImageView.isHidden)
        XCTAssertEqual(loader.loadCalls.map(\.id), ["abc"])

        loader.deliver(image: makeImage(color: .red))
        XCTAssertNotNil(cell.thumbnailImageView.image)
    }

    func test_phraseCell_reuse_clearsThumbnail() {
        let cell = makePhraseCell()
        cell.configureThumbnail(assetID: "abc", loader: loader)
        loader.deliver(image: makeImage(color: .red))
        XCTAssertNotNil(cell.thumbnailImageView.image)

        cell.prepareForReuse()
        XCTAssertTrue(cell.thumbnailImageView.isHidden)
        XCTAssertNil(cell.thumbnailImageView.image)
    }

    // MARK: - C2: category cell rendering

    func test_categoryCell_withNilAssetID_hidesThumbnail() {
        let cell = makeCategoryCell()
        cell.configureThumbnail(assetID: nil, loader: loader)
        XCTAssertTrue(cell.thumbnailImageView.isHidden)
    }

    func test_categoryCell_withAssetID_revealsThumbnail() {
        let cell = makeCategoryCell()
        cell.configureThumbnail(assetID: "xyz", loader: loader)
        XCTAssertFalse(cell.thumbnailImageView.isHidden)
        XCTAssertEqual(loader.loadCalls.map(\.id), ["xyz"])
    }

    // MARK: - C4: fixed cell height across thumbnail states

    func test_cellHeight_unchanged_byThumbnailPresence() {
        let cell = makePhraseCell()
        let fixedFrame = CGRect(x: 0, y: 0, width: 200, height: 120)
        cell.frame = fixedFrame
        cell.textLabel.text = "Hello"

        cell.configureThumbnail(assetID: nil, loader: loader)
        cell.layoutIfNeeded()
        let heightWithout = cell.frame.height

        cell.configureThumbnail(assetID: "abc", loader: loader)
        loader.deliver(image: makeImage(color: .blue))
        cell.layoutIfNeeded()
        let heightWith = cell.frame.height

        XCTAssertEqual(heightWith, heightWithout, "Cell height must not change when a thumbnail is added")
        XCTAssertEqual(heightWith, fixedFrame.height)
    }

    // MARK: - C5: accessibility

    func test_thumbnailImageView_isNotAccessibilityElement() {
        let cell = makePhraseCell()
        XCTAssertFalse(cell.thumbnailImageView.isAccessibilityElement,
                       "Photo is decorative; utterance/name remains the VoiceOver label")
    }

    func test_thumbnailImageView_isNotAccessibilityElement_onCategoryCell() {
        let cell = makeCategoryCell()
        XCTAssertFalse(cell.thumbnailImageView.isAccessibilityElement)
    }

    // MARK: - VC4: recording accessibility hint

    func test_configureRecordingAccessibility_setsHint_whenPlaysRecording() {
        let cell = makePhraseCell()
        cell.configureRecordingAccessibility(playsRecording: true)
        XCTAssertNotNil(cell.accessibilityHint)
        XCTAssertTrue(cell.accessibilityHint?.lowercased().contains("record") ?? false)
    }

    func test_configureRecordingAccessibility_clearsHint_whenNotPlayingRecording() {
        let cell = makePhraseCell()
        cell.configureRecordingAccessibility(playsRecording: true)
        cell.configureRecordingAccessibility(playsRecording: false)
        XCTAssertNil(cell.accessibilityHint)
    }

    func test_prepareForReuse_clearsRecordingAccessibilityHint() {
        let cell = makePhraseCell()
        cell.configureRecordingAccessibility(playsRecording: true)
        cell.prepareForReuse()
        XCTAssertNil(cell.accessibilityHint)
    }

    // MARK: - Helpers

    private func makePhraseCell() -> PresetItemCollectionViewCell {
        PresetItemCollectionViewCell(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
    }

    private func makeCategoryCell() -> CategoryItemCollectionViewCell {
        CategoryItemCollectionViewCell(frame: CGRect(x: 0, y: 0, width: 200, height: 120))
    }

    private func makeImage(color: UIColor, size: CGSize = CGSize(width: 32, height: 32)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}

private final class SpyThumbnailLoader: ThumbnailLoading {

    struct Call {
        let id: String
        let targetSize: CGSize
        let completion: (UIImage?) -> Void
    }

    private(set) var loadCalls: [Call] = []
    private(set) var lastToken: ThumbnailLoadToken?

    @discardableResult
    func loadThumbnail(
        id: String,
        targetSize: CGSize,
        completion: @escaping (UIImage?) -> Void
    ) -> ThumbnailLoadToken {
        loadCalls.append(Call(id: id, targetSize: targetSize, completion: completion))
        let token = ThumbnailLoadToken()
        lastToken = token
        return token
    }

    func deliver(image: UIImage?) {
        guard let call = loadCalls.last else { return }
        call.completion(image)
    }
}
