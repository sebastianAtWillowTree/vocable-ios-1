//
//  PhotoSystemSources.swift
//  Vocable
//
//  Production adapters wrapping UIKit/PhotosUI picker controllers
//  behind the PhotoSourceCoordinator protocols.
//

import UIKit
import PhotosUI

// MARK: - Camera availability

struct UIKitCameraAvailability: CameraAvailabilityProviding {
    var isCameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }
}

// MARK: - Choice presenter (action sheet)

struct AlertSourceChoicePresenter: PhotoSourceChoicePresenting {

    func presentChoice(
        from presenter: UIViewController,
        cameraEnabled: Bool,
        onCamera: @escaping () -> Void,
        onLibrary: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        let title = String(
            localized: "photo_source.alert.title",
            defaultValue: "Add Photo"
        )
        let cameraTitle = String(
            localized: "photo_source.alert.camera",
            defaultValue: "Take Photo"
        )
        let libraryTitle = String(
            localized: "photo_source.alert.library",
            defaultValue: "Choose from Library"
        )
        let cancelTitle = String(
            localized: "photo_source.alert.cancel",
            defaultValue: "Cancel"
        )

        let alert = UIAlertController(title: title, message: nil, preferredStyle: .actionSheet)
        if cameraEnabled {
            alert.addAction(UIAlertAction(title: cameraTitle, style: .default) { _ in onCamera() })
        }
        alert.addAction(UIAlertAction(title: libraryTitle, style: .default) { _ in onLibrary() })
        alert.addAction(UIAlertAction(title: cancelTitle, style: .cancel) { _ in onCancel() })

        // For iPad: anchor at the presenter's view center to avoid layout warnings.
        alert.popoverPresentationController?.sourceView = presenter.view
        alert.popoverPresentationController?.sourceRect = CGRect(
            x: presenter.view.bounds.midX,
            y: presenter.view.bounds.midY,
            width: 0,
            height: 0
        )

        presenter.present(alert, animated: true)
    }
}

// MARK: - System source provider

final class SystemPhotoSourceProvider: PhotoSourceProviding {

    private var activeCameraAdapter: CameraPickerAdapter?
    private var activeLibraryAdapter: LibraryPickerAdapter?

    func presentCamera(
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        let adapter = CameraPickerAdapter { [weak self] image in
            self?.activeCameraAdapter = nil
            completion(image)
        }
        activeCameraAdapter = adapter

        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = adapter
        presenter.present(picker, animated: true)
    }

    func presentLibrary(
        from presenter: UIViewController,
        completion: @escaping (UIImage?) -> Void
    ) {
        var configuration = PHPickerConfiguration()
        configuration.filter = .images
        configuration.selectionLimit = 1

        let picker = PHPickerViewController(configuration: configuration)

        let adapter = LibraryPickerAdapter { [weak self] image in
            self?.activeLibraryAdapter = nil
            completion(image)
        }
        activeLibraryAdapter = adapter
        picker.delegate = adapter
        presenter.present(picker, animated: true)
    }
}

// MARK: - Delegate adapters (held during picker lifetime)

private final class CameraPickerAdapter: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func imagePickerController(
        _ picker: UIImagePickerController,
        didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
    ) {
        let image = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
        picker.dismiss(animated: true) { [completion] in
            completion(image)
        }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        picker.dismiss(animated: true) { [completion] in
            completion(nil)
        }
    }
}

private final class LibraryPickerAdapter: NSObject, PHPickerViewControllerDelegate {
    private let completion: (UIImage?) -> Void

    init(completion: @escaping (UIImage?) -> Void) {
        self.completion = completion
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        guard let provider = results.first?.itemProvider,
              provider.canLoadObject(ofClass: UIImage.self) else {
            picker.dismiss(animated: true) { [completion] in
                completion(nil)
            }
            return
        }

        provider.loadObject(ofClass: UIImage.self) { [completion] object, _ in
            let image = object as? UIImage
            DispatchQueue.main.async {
                picker.dismiss(animated: true) {
                    completion(image)
                }
            }
        }
    }
}
