//
//  NSPersistentContainer+Shared.swift
//  Vocable AAC
//
//  Created by Chris Stroud on 2/21/20.
//  Copyright © 2020 WillowTree. All rights reserved.
//

import CoreData

extension NSPersistentContainer {

    /// Installs PhotoLifecycleObserver + AudioLifecycleObserver against
    /// the given container's viewContext and runs an initial orphan
    /// sweep against both asset stores. Returns the observer pair so the
    /// caller retains them for the lifetime of the container.
    ///
    /// Without this wiring, deletion / reassignment of imageAssetID and
    /// audioAssetID would silently leak files into Application Support
    /// indefinitely — the observers themselves only fire when alive and
    /// attached to a context.
    @discardableResult
    static func installAssetLifecycleObservers(
        on container: NSPersistentContainer,
        imageStore: ImageAssetStoring,
        audioStore: AudioAssetStoring
    ) -> (PhotoLifecycleObserver, AudioLifecycleObserver) {
        let photoObserver = PhotoLifecycleObserver(context: container.viewContext, store: imageStore)
        let audioObserver = AudioLifecycleObserver(context: container.viewContext, store: audioStore)
        try? photoObserver.sweepOrphans()
        try? audioObserver.sweepOrphans()
        return (photoObserver, audioObserver)
    }

    private struct Storage {
        static let container: NSPersistentContainer = {
            let container = NSPersistentContainer(name: "Phrases")
            container.loadPersistentStores { (_, error) in
                if let error = error {
                    assertionFailure("CoreData: Unresolved error \(error.localizedDescription)")
                    return
                }
                container.viewContext.automaticallyMergesChangesFromParent = true
            }
            return container
        }()

        /// Held for the lifetime of the process so observer NotificationCenter
        /// subscriptions stay attached. Nil only if either store fails to
        /// create its on-disk directory.
        static let observers: (PhotoLifecycleObserver, AudioLifecycleObserver)? = {
            guard let imageStore = try? ImageAssetStore(),
                  let audioStore = try? AudioAssetStore() else {
                assertionFailure("Could not construct asset stores for lifecycle observers")
                return nil
            }
            return NSPersistentContainer.installAssetLifecycleObservers(
                on: container,
                imageStore: imageStore,
                audioStore: audioStore
            )
        }()
    }

    static var shared: NSPersistentContainer {
        // Touch observers to ensure they're constructed before the first
        // save on the viewContext.
        _ = Storage.observers
        return Storage.container
    }
}
