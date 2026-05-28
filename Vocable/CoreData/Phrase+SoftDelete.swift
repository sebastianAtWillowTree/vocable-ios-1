//
//  Phrase+SoftDelete.swift
//  Vocable
//
//  Soft-delete for built-in phrases. Marks the row hidden AND detaches
//  any photo/audio assets so PhotoLifecycleObserver / AudioLifecycleObserver
//  can reclaim the underlying files. Without the asset-clear step, the
//  hidden phrase's row still references the files, the orphan sweep
//  treats them as referenced, and the files leak indefinitely.
//

import Foundation
import CoreData

extension Phrase {

    /// Soft-deletes this phrase:
    /// - sets `isUserRemoved = true` so it disappears from UI
    /// - clears `imageAssetID` and `audioAssetID` so the lifecycle
    ///   observers delete the underlying files on save
    ///
    /// Caller must save the context afterwards.
    func softDelete() {
        isUserRemoved = true
        imageAssetID = nil
        audioAssetID = nil
        prefersRecording = false
    }
}
