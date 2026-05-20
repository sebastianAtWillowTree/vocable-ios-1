//
//  CategoryPhotoEditorViewModel.swift
//  Vocable
//
//  Mirrors PhrasePhotoEditorViewModel for categories. Kept as a
//  separate type (rather than a generic parameterized one) so the
//  delegate method names remain semantically clear at the call site.
//

import Foundation
import CoreData

protocol CategoryPhotoEditorDelegate: AnyObject {
    func categoryPhotoEditor(
        _ editor: CategoryPhotoEditorViewModel,
        requestsAddOrChangePhotoFor categoryID: NSManagedObjectID
    )

    func categoryPhotoEditor(
        _ editor: CategoryPhotoEditorViewModel,
        requestsRemovalConfirmationFor categoryID: NSManagedObjectID,
        confirm: @escaping () -> Void
    )
}

final class CategoryPhotoEditorViewModel {

    enum Mode: Equatable {
        case empty
        case filled(assetID: String)
    }

    let categoryID: NSManagedObjectID
    private let context: NSManagedObjectContext
    private let store: ImageAssetStoring
    weak var delegate: CategoryPhotoEditorDelegate?

    init(
        categoryID: NSManagedObjectID,
        context: NSManagedObjectContext,
        store: ImageAssetStoring,
        delegate: CategoryPhotoEditorDelegate? = nil
    ) {
        self.categoryID = categoryID
        self.context = context
        self.store = store
        self.delegate = delegate
    }

    var mode: Mode {
        let object = context.object(with: categoryID)
        if let id = object.value(forKey: "imageAssetID") as? String {
            return .filled(assetID: id)
        }
        return .empty
    }

    func requestAddOrChange() {
        delegate?.categoryPhotoEditor(self, requestsAddOrChangePhotoFor: categoryID)
    }

    func requestRemove() {
        delegate?.categoryPhotoEditor(self, requestsRemovalConfirmationFor: categoryID) { [weak self] in
            self?.commitRemove()
        }
    }

    private func commitRemove() {
        let object = context.object(with: categoryID)
        object.setValue(nil, forKey: "imageAssetID")
        try? context.save()
    }
}
