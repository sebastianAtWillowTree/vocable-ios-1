//
//  PhotoSourceCoordinator.swift
//  Vocable
//
//  Orchestrates the caregiver-facing flow for picking a photo from
//  the camera or the photo library. Implementation seams:
//
//   - PhotoSourceChoicePresenting   : action-sheet style chooser UI
//   - PhotoSourceProviding          : the actual UIImagePickerController /
//                                     PHPickerViewController hand-off
//   - CameraAvailabilityProviding   : runtime check for camera hardware
//
//  All three are protocols so the coordinator's branching can be
//  exercised with stubs, and the production stack can be swapped in
//  at the call site.
//

import UIKit

protocol PhotoSourceChoicePresenting {
    func presentChoice(
        from presenter: UIViewController,
        cameraEnabled: Bool,
        onCamera: @escaping () -> Void,
        onLibrary: @escaping () -> Void,
        onCancel: @escaping () -> Void
    )
}

protocol PhotoSourceProviding {
    func presentCamera(
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    )

    func presentLibrary(
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    )
}

protocol CameraAvailabilityProviding {
    var isCameraAvailable: Bool { get }
}

final class PhotoSourceCoordinator {

    private let choicePresenter: PhotoSourceChoicePresenting
    private let sourceProvider: PhotoSourceProviding
    private let availability: CameraAvailabilityProviding

    init(
        choicePresenter: PhotoSourceChoicePresenting,
        sourceProvider: PhotoSourceProviding,
        availability: CameraAvailabilityProviding
    ) {
        self.choicePresenter = choicePresenter
        self.sourceProvider = sourceProvider
        self.availability = availability
    }

    /// Presents the source chooser. The completion fires once with the
    /// picked image, or with nil if the caregiver cancels at any step.
    func present(
        from viewController: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        choicePresenter.presentChoice(
            from: viewController,
            cameraEnabled: availability.isCameraAvailable,
            onCamera: { [sourceProvider] in
                sourceProvider.presentCamera(from: viewController, completion: completion)
            },
            onLibrary: { [sourceProvider] in
                sourceProvider.presentLibrary(from: viewController, completion: completion)
            },
            onCancel: {
                completion(nil)
            }
        )
    }
}
