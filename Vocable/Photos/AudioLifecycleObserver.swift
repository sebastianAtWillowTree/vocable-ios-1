//
//  AudioLifecycleObserver.swift
//  Vocable
//
//  Bridges Core Data save notifications to the audio asset store.
//  Same shape as PhotoLifecycleObserver; kept separate so each
//  store owns its own cleanup responsibility.
//

import Foundation
import CoreData

final class AudioLifecycleObserver {

    private let context: NSManagedObjectContext
    private let store: AudioAssetStoring
    private var pendingDeletions: Set<String> = []

    init(context: NSManagedObjectContext, store: AudioAssetStoring) {
        self.context = context
        self.store = store
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextWillSave(_:)),
            name: .NSManagedObjectContextWillSave,
            object: context
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(contextDidSave(_:)),
            name: .NSManagedObjectContextDidSave,
            object: context
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    func sweepOrphans() throws {
        let referenced = try collectReferencedAssetIDs()
        let onDisk = Set(store.allAssetIDs())
        for orphan in onDisk.subtracting(referenced) {
            try store.delete(id: orphan)
        }
    }

    // MARK: - Save notifications

    @objc private func contextWillSave(_ note: Notification) {
        var ids: Set<String> = []

        for object in context.deletedObjects {
            guard object.entity.attributesByName["audioAssetID"] != nil else { continue }
            if let id = object.value(forKey: "audioAssetID") as? String {
                ids.insert(id)
            }
        }

        for object in context.updatedObjects {
            guard object.entity.attributesByName["audioAssetID"] != nil else { continue }
            guard object.changedValues().keys.contains("audioAssetID") else { continue }
            if let previous = object.committedValues(forKeys: ["audioAssetID"])["audioAssetID"] as? String {
                ids.insert(previous)
            }
        }

        pendingDeletions = ids
    }

    @objc private func contextDidSave(_ note: Notification) {
        defer { pendingDeletions.removeAll() }
        for id in pendingDeletions {
            try? store.delete(id: id)
        }
    }

    // MARK: - Helpers

    private func collectReferencedAssetIDs() throws -> Set<String> {
        var ids = Set<String>()
        let request = NSFetchRequest<NSManagedObject>(entityName: "Phrase")
        request.propertiesToFetch = ["audioAssetID"]
        let results = try context.fetch(request)
        for object in results {
            if let id = object.value(forKey: "audioAssetID") as? String {
                ids.insert(id)
            }
        }
        return ids
    }
}
