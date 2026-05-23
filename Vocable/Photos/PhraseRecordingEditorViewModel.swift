//
//  PhraseRecordingEditorViewModel.swift
//  Vocable
//
//  Mediates voice-recording-related actions for a single phrase:
//  - Reports whether the phrase has a recording (Mode)
//  - Dispatches "add" / "change" requests through a delegate
//  - Owns the destructive "remove" flow (confirmation -> persist nil)
//
//  Mirrors PhrasePhotoEditorViewModel one-for-one so the call sites
//  in EditPhrasesViewController stay symmetrical.
//

import Foundation
import CoreData

protocol PhraseRecordingEditorDelegate: AnyObject {
    /// Caller should present the VoiceRecorderViewController.
    func phraseRecordingEditor(
        _ editor: PhraseRecordingEditorViewModel,
        requestsAddOrChangeRecordingFor phraseID: NSManagedObjectID
    )

    /// Caller should present a confirmation alert. If the caregiver
    /// confirms, invoke `confirm()`.
    func phraseRecordingEditor(
        _ editor: PhraseRecordingEditorViewModel,
        requestsRemovalConfirmationFor phraseID: NSManagedObjectID,
        confirm: @escaping () -> Void
    )
}

final class PhraseRecordingEditorViewModel {

    enum Mode: Equatable {
        case empty
        case filled(assetID: String)
    }

    let phraseID: NSManagedObjectID
    private let context: NSManagedObjectContext
    private let store: AudioAssetStoring
    weak var delegate: PhraseRecordingEditorDelegate?

    init(
        phraseID: NSManagedObjectID,
        context: NSManagedObjectContext,
        store: AudioAssetStoring,
        delegate: PhraseRecordingEditorDelegate? = nil
    ) {
        self.phraseID = phraseID
        self.context = context
        self.store = store
        self.delegate = delegate
    }

    var mode: Mode {
        let object = context.object(with: phraseID)
        if let id = object.value(forKey: "audioAssetID") as? String {
            return .filled(assetID: id)
        }
        return .empty
    }

    /// Current state of the playback preference toggle.
    var prefersRecording: Bool {
        let object = context.object(with: phraseID)
        return (object.value(forKey: "prefersRecording") as? Bool) ?? false
    }

    /// Flip the playback preference. Only meaningful when a recording
    /// is attached; calling this with no recording is a no-op so the
    /// toggle can't be left "on" while pointing at nothing.
    func togglePrefersRecording() {
        guard case .filled = mode else { return }
        let object = context.object(with: phraseID)
        let current = (object.value(forKey: "prefersRecording") as? Bool) ?? false
        object.setValue(!current, forKey: "prefersRecording")
        try? context.save()
    }

    func requestAddOrChange() {
        delegate?.phraseRecordingEditor(self, requestsAddOrChangeRecordingFor: phraseID)
    }

    func requestRemove() {
        delegate?.phraseRecordingEditor(self, requestsRemovalConfirmationFor: phraseID) { [weak self] in
            self?.commitRemove()
        }
    }

    private func commitRemove() {
        let object = context.object(with: phraseID)
        object.setValue(nil, forKey: "audioAssetID")
        // If the recording is gone, prefersRecording must be false to
        // avoid pointing at an absent asset on playback.
        object.setValue(false, forKey: "prefersRecording")
        try? context.save()
    }
}
