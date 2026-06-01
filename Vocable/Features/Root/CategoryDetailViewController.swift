//
//  CategoryDetailViewController.swift
//  Vocable
//
//  Created by Chris Stroud on 5/1/20.
//  Copyright © 2020 WillowTree. All rights reserved.
//

import UIKit
import Combine
import CoreData
import AVFoundation

class CategoryDetailViewController: PagingCarouselViewController, NSFetchedResultsControllerDelegate {
    private typealias DataSource = CarouselCollectionViewDataSourceProxy<String, CategoryItem>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<String, CategoryItem>

    var category: Category!
    @PublishedValue private(set) var lastUtterance: String?

    private var disposables = Set<AnyCancellable>()

    private enum CategoryItem: Hashable {
        case persistedPhrase(NSManagedObjectID)
        case addNewPhrase
    }

    private var dataSourceProxy: DataSource!

    /// Observes Core Data saves so that attribute-only changes
    /// (e.g. Phrase.imageAssetID after a photo save) trigger an
    /// explicit cell reconfigure. NSFetchedResultsController's
    /// `reconfiguredItemIdentifiers` on iOS 15+ only tracks changes
    /// to properties referenced by the FRC's sort/predicate — pure
    /// attribute updates outside that set don't propagate and the
    /// phrase tile stays on the old thumbnail until app restart.
    private var contextDidSaveObserver: NSObjectProtocol?

    private lazy var fetchRequest: NSFetchRequest<Phrase> = {
        let request: NSFetchRequest<Phrase> = Phrase.fetchRequest()

        var predicate = !Predicate(\Phrase.isUserRemoved)
        if category.identifier == Category.Identifier.recents {
            predicate &= Predicate(\Phrase.lastSpokenDate, notEqualTo: nil)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Phrase.lastSpokenDate, ascending: false)]
            request.fetchLimit = 9
        } else {
            predicate &= Predicate(\Phrase.category, equalTo: self.category)
            request.sortDescriptors = [NSSortDescriptor(keyPath: \Phrase.creationDate, ascending: false)]
        }
        request.predicate = predicate
        return request
    }()

    private lazy var frc = NSFetchedResultsController<Phrase>(fetchRequest: self.fetchRequest,
                                                              managedObjectContext: NSPersistentContainer.shared.viewContext,
                                                              sectionNameKeyPath: nil,
                                                              cacheName: nil)

    convenience init(category: Category) {
        self.init(nibName: nil, bundle: nil)
        self.category = category
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        dataSourceProxy = makeDataSource()
        
        edgesForExtendedLayout = UIRectEdge.all.subtracting(.top)
        view.layoutMargins.top = 4

        assert(category != nil, "Category not assigned")

        collectionView.register(PresetItemCollectionViewCell.self, forCellWithReuseIdentifier: PresetItemCollectionViewCell.reuseIdentifier)
        collectionView.register(AddPhraseCollectionViewCell.self, forCellWithReuseIdentifier: AddPhraseCollectionViewCell.reuseIdentifier)
        collectionView.delaysContentTouches = false

        updateLayoutForCurrentTraitCollection()

        frc.delegate = self
        observeCoreDataSaves()
    }

    deinit {
        if let observer = contextDidSaveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func observeCoreDataSaves() {
        contextDidSaveObserver = NotificationCenter.default.addObserver(
            forName: .NSManagedObjectContextDidSave,
            object: frc.managedObjectContext,
            queue: .main
        ) { [weak self] notification in
            self?.handleContextDidSave(notification)
        }
    }

    private func handleContextDidSave(_ notification: Notification) {
        guard let info = notification.userInfo else { return }
        var changedPhraseIDs: Set<NSManagedObjectID> = []
        for key in [NSUpdatedObjectsKey, NSRefreshedObjectsKey] {
            guard let objects = info[key] as? Set<NSManagedObject> else { continue }
            for object in objects where object is Phrase {
                changedPhraseIDs.insert(object.objectID)
            }
        }
        guard !changedPhraseIDs.isEmpty else { return }

        var snapshot = dataSourceProxy.snapshot()
        let items = changedPhraseIDs
            .map(CategoryItem.persistedPhrase)
            .filter { snapshot.itemIdentifiers.contains($0) }
        guard !items.isEmpty else { return }

        if #available(iOS 15, *) {
            snapshot.reconfigureItems(items)
        } else {
            snapshot.reloadItems(items)
        }
        dataSourceProxy.apply(snapshot, animatingDifferences: false)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        try? frc.performFetch()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayoutForCurrentTraitCollection()
    }

    private func updateLayoutForCurrentTraitCollection() {

        collectionView.layout.interItemSpacing = .uniform(8)
        switch sizeClass {
        case .hRegular_vRegular:
            collectionView.layout.numberOfColumns = .fixedCount(3)
            collectionView.layout.numberOfRows = .flexible(minHeight: .absolute(120))
        case .hCompact_vRegular:
            collectionView.layout.numberOfColumns = .fixedCount(2)
            collectionView.layout.numberOfRows = .fixedCount(4)
        case .hCompact_vCompact, .hRegular_vCompact:
            collectionView.layout.numberOfColumns = .fixedCount(3)
            collectionView.layout.numberOfRows = .fixedCount(2)
        default:
            break
        }
    }

    private func makeDataSource() -> DataSource {
        DataSource(collectionView: collectionView) { [weak self] (collectionView, indexPath, item) -> UICollectionViewCell? in
            guard let self = self else { return nil }
            let cell: UICollectionViewCell
            switch item {
            case .persistedPhrase:
                cell = collectionView.dequeueReusableCell(withReuseIdentifier: PresetItemCollectionViewCell.reuseIdentifier, for: indexPath)
            case .addNewPhrase:
                cell = collectionView.dequeueReusableCell(withReuseIdentifier: AddPhraseCollectionViewCell.reuseIdentifier, for: indexPath)
            }
            self.configureCell(cell, for: item, at: indexPath)
            return cell
        }
    }

    private lazy var thumbnailLoader: ThumbnailLoading? = {
        guard let store = try? ImageAssetStore() else { return nil }
        return ThumbnailLoader(store: store)
    }()

    /// Full-resolution store used to flash the phrase photo on
    /// selection (the thumbnail loader downscales, which we don't want
    /// for the full-screen presentation).
    private lazy var imageStore: ImageAssetStoring? = try? ImageAssetStore()

    private lazy var audioStore: AudioAssetStoring? = try? AudioAssetStore()
    private lazy var audioPlayback: AudioPlaybackServicing = AudioPlaybackService()

    private func configureCell(_ cell: UICollectionViewCell, for item: CategoryItem, at indexPath: IndexPath) {
        switch item {
        case .persistedPhrase(let objectId):
            let cell = cell as? PresetItemCollectionViewCell

            guard let phrase = Phrase.fetchObject(in: self.frc.managedObjectContext, matching: objectId) else { return }
            cell?.textLabel.text = phrase.utterance
            cell?.accessibilityIdentifier = phrase.identifier
            if let loader = thumbnailLoader {
                cell?.configureThumbnail(assetID: phrase.imageAssetID, loader: loader)
            }
            let playsRecording = (phrase.audioAssetID != nil) && phrase.prefersRecording
            cell?.configureRecordingAccessibility(playsRecording: playsRecording)
        case .addNewPhrase:
            let cell = cell as? AddPhraseCollectionViewCell
                cell?.accessibilityID = .root.addPhraseButton
        }
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let pageCountBefore = collectionView.layout.pagesPerSection
        let fetchedSnapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>

        var updatedSnapshot = makeSnapshot(from: fetchedSnapshot)

        if #available(iOS 15, *) {
            // Propagate reconfigured items through the mapItemIdentifier
            // rebuild — otherwise an attribute-only change (e.g. a new
            // imageAssetID after a photo save) is invisible to the diffable
            // data source and the cell stays stale until app restart.
            let reconfigured = fetchedSnapshot.reconfiguredItemIdentifiers
                .map(CategoryItem.persistedPhrase)
                .filter { updatedSnapshot.itemIdentifiers.contains($0) }
            if !reconfigured.isEmpty {
                updatedSnapshot.reconfigureItems(reconfigured)
            }
            dataSourceProxy.apply(updatedSnapshot, animatingDifferences: false)
        } else {
            dataSourceProxy.apply(updatedSnapshot, animatingDifferences: true) { [weak self] in
                guard let self = self, #unavailable(iOS 15) else { return }

                // This is effectively the same iOS 14 fix we have for
                // screens that have been updated for VocableListCell
                let visibleIndexPaths = self.collectionView.indexPathsForVisibleItems
                self.dataSourceProxy.performActions(on: visibleIndexPaths) { elements in
                    guard let cell = self.collectionView.cellForItem(at: elements.virtualIndexPath) else { return }
                    self.configureCell(cell, for: elements.itemIdentifier, at: elements.virtualIndexPath)
                }
            }
        }
        let pageCountAfter = collectionView.layout.pagesPerSection

        if snapshot.itemIdentifiers.isEmpty {
            installEmptyStateIfNeeded()
        } else {
            removeEmptyStateIfNeeded()
        }

        if pageCountBefore < 2, pageCountAfter > 1 {
            collectionView.scrollToMiddleSection(animated: false)
        }
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {

        if indexPath != collectionView.indexPathForGazedItem {
            collectionView.deselectItem(at: indexPath, animated: true)
        }

        guard let item = dataSourceProxy.itemIdentifier(for: indexPath) else { return }

        switch item {
        case .persistedPhrase(let objectId):
            let context = NSPersistentContainer.shared.newBackgroundContext()
            // Captured on the main thread so the lazy store isn't first
            // touched from the background context queue.
            let imageStore = self.imageStore

            context.perform { [weak self] in
                guard
                    let self = self,
                    let phrase = Phrase.fetchObject(in: context, matching: objectId),
                    let utterance = phrase.utterance
                else {
                    self?.lastUtterance = nil
                    return
                }

                self.lastUtterance = utterance

                Analytics.shared.track(.phraseSelected(phrase, of: self.category))

                if self.category.identifier != Category.Identifier.recents {
                    phrase.lastSpokenDate = Date()
                    try? context.save()
                }

                let assetID = phrase.audioAssetID
                let prefersRecording = phrase.prefersRecording
                // Decode the photo off the main thread; flashed on
                // selection regardless of the audio path below.
                let flashImage: UIImage? = phrase.imageAssetID.flatMap { imageStore?.load(id: $0) }
                DispatchQueue.main.async {
                    if let flashImage, let window = self.view.window {
                        FullScreenImageOverlay.shared.show(image: flashImage, in: window)
                    }
                    if prefersRecording,
                       let assetID,
                       let store = self.audioStore,
                       let url = store.url(for: assetID),
                       (try? self.audioPlayback.play(url: url)) != nil {
                        // Played the recording — skip TTS.
                        return
                    }
                    self.speak(utterance, forItemAt: indexPath)
                }
            }
        case .addNewPhrase:
            addNewPhraseButtonSelected()
        }

    }

    private func makeSnapshot(from fetchedSnapshot: NSDiffableDataSourceSnapshot<String, NSManagedObjectID>) -> Snapshot {
        var updatedSnapshot = fetchedSnapshot.mapItemIdentifier(CategoryItem.persistedPhrase)

        if category.allowsCustomPhrases, updatedSnapshot.numberOfItems != 0 {
            updatedSnapshot.appendItems([.addNewPhrase])
        }

        return updatedSnapshot
    }

    private func installEmptyStateIfNeeded() {
        guard collectionView.backgroundView == nil else { return }
        paginationView.isHidden = true
        if category.identifier == Category.Identifier.recents {
            collectionView.backgroundView = EmptyStateView(type: EmptyStateType.recents)
        } else {
            collectionView.backgroundView = EmptyStateView(type: EmptyStateType.phraseCollection, action: { [weak self] in
                self?.addNewPhraseButtonSelected()
            })
        }
    }

    private func removeEmptyStateIfNeeded() {
        paginationView.isHidden = false
        collectionView.backgroundView = nil
    }

    @IBAction func addNewPhraseButtonSelected() {
        let vc = TextEditorViewController()
        let context = NSPersistentContainer.shared.newBackgroundContext()
        vc.delegate = PhraseEditorConfigurationProvider(categoryIdentifier: category.objectID, context: context)
        vc.modalPresentationStyle = .fullScreen
        present(vc, animated: true)
    }
}
