//
//  PhotoSourceCoordinatorTests.swift
//  VocableTests
//

import XCTest
import UIKit
@testable import Vocable

final class PhotoSourceCoordinatorTests: XCTestCase {

    private var hostViewController: UIViewController!
    private var choicePresenter: SpyChoicePresenter!
    private var sourceProvider: SpySourceProvider!

    override func setUpWithError() throws {
        try super.setUpWithError()
        hostViewController = UIViewController()
        choicePresenter = SpyChoicePresenter()
        sourceProvider = SpySourceProvider()
    }

    override func tearDownWithError() throws {
        hostViewController = nil
        choicePresenter = nil
        sourceProvider = nil
        try super.tearDownWithError()
    }

    // MARK: - Tests

    func test_present_offersCameraOption_whenCameraAvailable() {
        let coordinator = makeCoordinator(cameraAvailable: true)
        coordinator.present(from: hostViewController) { _ in }
        XCTAssertEqual(choicePresenter.presentChoiceCalls.count, 1)
        XCTAssertEqual(choicePresenter.presentChoiceCalls[0].cameraEnabled, true)
    }

    func test_present_hidesCameraOption_whenCameraUnavailable() {
        let coordinator = makeCoordinator(cameraAvailable: false)
        coordinator.present(from: hostViewController) { _ in }
        XCTAssertEqual(choicePresenter.presentChoiceCalls.count, 1)
        XCTAssertEqual(choicePresenter.presentChoiceCalls[0].cameraEnabled, false)
    }

    func test_choosingCamera_invokesSourceProviderCamera() {
        let coordinator = makeCoordinator(cameraAvailable: true)
        var receivedImage: UIImage??
        coordinator.present(from: hostViewController) { image in
            receivedImage = .some(image)
        }
        choicePresenter.presentChoiceCalls[0].onCamera()
        XCTAssertEqual(sourceProvider.presentCameraCount, 1)
        XCTAssertEqual(sourceProvider.presentLibraryCount, 0)
        XCTAssertNil(receivedImage, "Completion should not fire yet")

        let testImage = TestSupport.solidImage(color: .red)
        sourceProvider.deliverCameraImage(testImage)

        XCTAssertEqual(receivedImage.flatMap { $0 }?.size, testImage.size)
    }

    func test_choosingLibrary_invokesSourceProviderLibrary() {
        let coordinator = makeCoordinator(cameraAvailable: true)
        var receivedImage: UIImage??
        coordinator.present(from: hostViewController) { image in
            receivedImage = .some(image)
        }
        choicePresenter.presentChoiceCalls[0].onLibrary()
        XCTAssertEqual(sourceProvider.presentLibraryCount, 1)
        XCTAssertEqual(sourceProvider.presentCameraCount, 0)
        XCTAssertNil(receivedImage, "Completion should not fire yet")

        let testImage = TestSupport.solidImage(color: .green)
        sourceProvider.deliverLibraryImage(testImage)

        XCTAssertEqual(receivedImage.flatMap { $0 }?.size, testImage.size)
    }

    func test_choosingLibrary_thenCancellingPicker_propagatesNil() {
        let coordinator = makeCoordinator(cameraAvailable: true)
        var receivedImage: UIImage??
        coordinator.present(from: hostViewController) { image in
            receivedImage = .some(image)
        }
        choicePresenter.presentChoiceCalls[0].onLibrary()
        sourceProvider.deliverLibraryImage(nil)
        XCTAssertNotNil(receivedImage)
        XCTAssertNil(receivedImage.flatMap { $0 })
    }

    func test_cancelChoice_immediatelyDeliversNilCompletion() {
        let coordinator = makeCoordinator(cameraAvailable: true)
        var receivedImage: UIImage??
        coordinator.present(from: hostViewController) { image in
            receivedImage = .some(image)
        }
        choicePresenter.presentChoiceCalls[0].onCancel()
        XCTAssertEqual(sourceProvider.presentCameraCount, 0)
        XCTAssertEqual(sourceProvider.presentLibraryCount, 0)
        XCTAssertNotNil(receivedImage)
        XCTAssertNil(receivedImage.flatMap { $0 })
    }

    // MARK: - Helpers

    private func makeCoordinator(cameraAvailable: Bool) -> PhotoSourceCoordinator {
        PhotoSourceCoordinator(
            choicePresenter: choicePresenter,
            sourceProvider: sourceProvider,
            availability: StubCameraAvailability(isCameraAvailable: cameraAvailable)
        )
    }
}

// MARK: - Test doubles

private struct StubCameraAvailability: CameraAvailabilityProviding {
    let isCameraAvailable: Bool
}

private final class SpyChoicePresenter: PhotoSourceChoicePresenting {
    struct Call {
        let cameraEnabled: Bool
        let onCamera: () -> Void
        let onLibrary: () -> Void
        let onCancel: () -> Void
    }

    private(set) var presentChoiceCalls: [Call] = []

    func presentChoice(
        from presenter: UIViewController,
        cameraEnabled: Bool,
        onCamera: @escaping () -> Void,
        onLibrary: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        presentChoiceCalls.append(
            Call(
                cameraEnabled: cameraEnabled,
                onCamera: onCamera,
                onLibrary: onLibrary,
                onCancel: onCancel
            )
        )
    }
}

private final class SpySourceProvider: PhotoSourceProviding {
    private(set) var presentCameraCount = 0
    private(set) var presentLibraryCount = 0
    private var cameraCompletion: ((UIImage?) -> Void)?
    private var libraryCompletion: ((UIImage?) -> Void)?

    func presentCamera(
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        presentCameraCount += 1
        cameraCompletion = completion
    }

    func presentLibrary(
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        presentLibraryCount += 1
        libraryCompletion = completion
    }

    func deliverCameraImage(_ image: UIImage?) {
        cameraCompletion?(image)
        cameraCompletion = nil
    }

    func deliverLibraryImage(_ image: UIImage?) {
        libraryCompletion?(image)
        libraryCompletion = nil
    }
}

private enum TestSupport {
    static func solidImage(color: UIColor, size: CGSize = CGSize(width: 8, height: 8)) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { ctx in
            color.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
    }
}
