//
//  PhotoLifecycleObserver.swift
//  Vocable
//
//  Bridges Core Data lifecycle events to the image asset store.
//  - Deletes a phrase/category file when its entity is deleted.
//  - Deletes the previous file when imageAssetID is reassigned.
//  - Provides an orphan sweep called once per app launch.
//

import Foundation
import CoreData

final class PhotoLifecycleObserver {

    private let context: NSManagedObjectContext
    private let store: ImageAssetStoring
    private var pendingDeletions: Set<String> = []

    init(context: NSManagedObjectContext, store: ImageAssetStoring) {
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
            guard object.entity.attributesByName["imageAssetID"] != nil else { continue }
            if let id = object.value(forKey: "imageAssetID") as? String {
                ids.insert(id)
            }
        }

        for object in context.updatedObjects {
            guard object.entity.attributesByName["imageAssetID"] != nil else { continue }
            guard object.changedValues().keys.contains("imageAssetID") else { continue }
            if let previous = object.committedValues(forKeys: ["imageAssetID"])["imageAssetID"] as? String {
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
        for entityName in ["Phrase", "Category"] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.propertiesToFetch = ["imageAssetID"]
            let results = try context.fetch(request)
            for object in results {
                if let id = object.value(forKey: "imageAssetID") as? String {
                    ids.insert(id)
                }
            }
        }
        return ids
    }
}
