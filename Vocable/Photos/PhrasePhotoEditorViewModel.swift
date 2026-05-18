//
//  PhrasePhotoEditorViewModel.swift
//  Vocable
//
//  Mediates photo-related actions for a single phrase:
//  - Reports whether the phrase has a photo (Mode)
//  - Dispatches "add" / "change" requests through a delegate
//  - Owns the destructive "remove" flow (confirmation -> persist nil)
//

import Foundation
import CoreData

protocol PhrasePhotoEditorDelegate: AnyObject {
    /// Caller should present a source picker (camera / library).
    func phrasePhotoEditor(
        _ editor: PhrasePhotoEditorViewModel,
        requestsAddOrChangePhotoFor phraseID: NSManagedObjectID
    )

    /// Caller should present a confirmation alert. If the caregiver
    /// confirms, invoke `confirm()`.
    func phrasePhotoEditor(
        _ editor: PhrasePhotoEditorViewModel,
        requestsRemovalConfirmationFor phraseID: NSManagedObjectID,
        confirm: @escaping () -> Void
    )
}

final class PhrasePhotoEditorViewModel {

    enum Mode: Equatable {
        case empty
        case filled(assetID: String)
    }

    let phraseID: NSManagedObjectID
    private let context: NSManagedObjectContext
    private let store: ImageAssetStoring
    weak var delegate: PhrasePhotoEditorDelegate?

    init(
        phraseID: NSManagedObjectID,
        context: NSManagedObjectContext,
        store: ImageAssetStoring,
        delegate: PhrasePhotoEditorDelegate? = nil
    ) {
        self.phraseID = phraseID
        self.context = context
        self.store = store
        self.delegate = delegate
    }

    var mode: Mode {
        let object = context.object(with: phraseID)
        if let id = object.value(forKey: "imageAssetID") as? String {
            return .filled(assetID: id)
        }
        return .empty
    }

    /// Single entry point used for both "Add" (when empty) and "Change" (when filled).
    /// The source picker presented by the delegate replaces any existing photo.
    func requestAddOrChange() {
        delegate?.phrasePhotoEditor(self, requestsAddOrChangePhotoFor: phraseID)
    }

    /// Starts the destructive removal flow. The delegate is expected to confirm
    /// with the user before invoking the supplied `confirm` closure.
    func requestRemove() {
        delegate?.phrasePhotoEditor(self, requestsRemovalConfirmationFor: phraseID) { [weak self] in
            self?.commitRemove()
        }
    }

    private func commitRemove() {
        let object = context.object(with: phraseID)
        object.setValue(nil, forKey: "imageAssetID")
        try? context.save()
    }
}
