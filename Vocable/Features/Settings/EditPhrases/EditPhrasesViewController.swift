//
//  EditPhrasesViewController.swift
//  Vocable AAC
//
//  Created by Thomas Shealy on 3/31/20.
//  Copyright © 2020 WillowTree. All rights reserved.
//

import UIKit
import Combine
import CoreData

final class EditPhrasesViewController: PagingCarouselViewController, NSFetchedResultsControllerDelegate {

    var category: Category!
    private var disposables = Set<AnyCancellable>()

    private lazy var sourceCoordinator = PhotoSourceCoordinator(
        choicePresenter: AlertSourceChoicePresenter(),
        sourceProvider: SystemPhotoSourceProvider(),
        availability: UIKitCameraAvailability()
    )

    private lazy var enhanceCoordinator = PhotoEnhanceCoordinator(
        gate: ExperimentalFeatureGate(),
        picker: AlertVariantPicker(),
        subjectLifter: VisionSubjectLiftService(),
        stylizer: ImagePlaygroundStylizer(),
        progress: AlertEnhancementProgress()
    )

    private lazy var dataSourceProxy = makeDataSourceProxy()

    private lazy var fetchRequest: NSFetchRequest<Phrase> = {
        let request: NSFetchRequest<Phrase> = Phrase.fetchRequest()
        request.predicate = Predicate(\Phrase.category, equalTo: category) && !Predicate(\Phrase.isUserRemoved)
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Phrase.creationDate, ascending: false)]
        return request
    }()

    private lazy var fetchResultsController = NSFetchedResultsController<Phrase>(fetchRequest: self.fetchRequest,
                                                                                 managedObjectContext: NSPersistentContainer.shared.viewContext,
                                                                                 sectionNameKeyPath: nil,
                                                                                 cacheName: nil)

    override func viewDidLoad() {
        super.viewDidLoad()

        assert(category != nil, "Category not provided")

        updateLayoutForCurrentTraitCollection()

        fetchResultsController.delegate = self
        try? fetchResultsController.performFetch()

        setupNavigationBar()
        setupCollectionView()
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        updateBackgroundViewLayoutMargins()
    }

    private func setupNavigationBar() {
        navigationBar.title = category.name
        navigationBar.rightButton = {
            let button = GazeableButton(frame: .zero)
            button.setImage(UIImage(systemName: "plus"), for: .normal)
            button.accessibilityID = .settings.editPhrases.addPhraseButton
            button.addTarget(self, action: #selector(addPhrasePressed), for: .primaryActionTriggered)
            return button
        }()
    }

    private func setupCollectionView() {
        collectionView.backgroundColor = .collectionViewBackgroundColor
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)

        updateLayoutForCurrentTraitCollection()
    }

    private func updateLayoutForCurrentTraitCollection() {
        collectionView.layout.interItemSpacing = .init(interRowSpacing: 8, interColumnSpacing: 30)

        switch sizeClass {
        case .hRegular_vRegular:
            collectionView.layout.numberOfColumns = .fixedCount(2)
            collectionView.layout.numberOfRows = .flexible(minHeight: .absolute(100))
        case .hCompact_vRegular:
            collectionView.layout.numberOfColumns = .fixedCount(1)
            collectionView.layout.numberOfRows = .flexible(minHeight: .absolute(64))
        case .hCompact_vCompact, .hRegular_vCompact:
            collectionView.layout.numberOfColumns = .fixedCount(2)
            collectionView.layout.numberOfRows = .flexible(minHeight: .absolute(64))
        default:
            break
        }
    }

    func collectionView(_ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath) -> Bool {
        return false
    }

    func collectionView(_ collectionView: UICollectionView, shouldHighlightItemAt indexPath: IndexPath) -> Bool {
        return false
    }

    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChangeContentWith snapshot: NSDiffableDataSourceSnapshotReference) {

        let pageCountBefore = collectionView.layout.pagesPerSection
        let snapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        dataSourceProxy.apply(snapshot, animatingDifferences: false)

        let pageCountAfter = collectionView.layout.pagesPerSection

        if snapshot.itemIdentifiers.isEmpty {
            installEmptyStateIfNeeded()
        } else {
            removeEmptyStateIfNeeded()
        }

        if pageCountBefore < 2, pageCountAfter > 1 {
            collectionView.scrollToMiddleSection(animated: UIView.areAnimationsEnabled)
        }
    }

    private func installEmptyStateIfNeeded() {
        guard collectionView.backgroundView == nil else { return }
        paginationView.isHidden = true
        collectionView.backgroundView = EmptyStateView(type: EmptyStateType.phraseCollection, action: addPhrasePressed)
        updateBackgroundViewLayoutMargins()
    }

    private func removeEmptyStateIfNeeded() {
        paginationView.isHidden = false
        collectionView.backgroundView = nil
    }

    private func updateBackgroundViewLayoutMargins() {
        guard let backgroundView = collectionView.backgroundView else { return }
        backgroundView.directionalLayoutMargins.leading = view.directionalLayoutMargins.leading
        backgroundView.directionalLayoutMargins.trailing = view.directionalLayoutMargins.trailing
    }

    // MARK: Actions
    @IBAction private func addPhrasePressed() {
        let viewController = TextEditorViewController()
        let context = NSPersistentContainer.shared.newBackgroundContext()
        viewController.delegate = PhraseEditorConfigurationProvider(categoryIdentifier: category.objectID,
                                                           context: context)

        viewController.modalPresentationStyle = .fullScreen
        present(viewController, animated: true)
    }

    fileprivate func presentDeletionPromptForPhrase(with id: NSManagedObjectID) {

        func deleteAction() {
            self.deletePhrase(with: id)
        }

        let title = String(localized: "category_editor.alert.delete_phrase_confirmation.title")
        let deleteButtonTitle = String(localized: "category_editor.alert.delete_phrase_confirmation.button.delete.title")
        let cancelButtonTitle = String(localized: "category_editor.alert.delete_phrase_confirmation.button.cancel.title")

        let alert = GazeableAlertViewController(alertTitle: title)
        alert.addAction(.cancel(withTitle: cancelButtonTitle))
        alert.addAction(.delete(withTitle: deleteButtonTitle, handler: deleteAction))
        self.present(alert, animated: true)
    }

    private func deletePhrase(with id: NSManagedObjectID) {
        let context = NSPersistentContainer.shared.viewContext
        guard let phrase = context.object(with: id) as? Phrase else { return }

        if phrase.isUserGenerated {
            context.delete(phrase)
        } else {
            phrase.isUserRemoved = true
        }

        do {
            try context.save()
        } catch {
            assertionFailure("Could not save phrase: \(error)")
        }
    }

    fileprivate func presentEditorForPhrase(with id: NSManagedObjectID) {
        let vc = TextEditorViewController()
        let context = NSPersistentContainer.shared.newBackgroundContext()
        vc.delegate = PhraseEditorConfigurationProvider(categoryIdentifier: category.objectID,
                                               phraseIdentifier: id,
                                               context: context)

        present(vc, animated: true)
    }

    private func handleDismissAlert() {

        func discardChangesAction() {
            self.navigationController?.popViewController(animated: true)
        }

        let title = String(localized: "phrase_editor.alert.cancel_editing_confirmation.title")
        let discardButtonTitle = String(localized: "phrase_editor.alert.cancel_editing_confirmation.button.discard.title")
        let continueButtonTitle = String(localized: "phrase_editor.alert.cancel_editing_confirmation.button.continue_editing.title")
        let alert = GazeableAlertViewController(alertTitle: title)
        alert.addAction(.continueEditing(withTitle: continueButtonTitle))
        alert.addAction(.discardChanges(withTitle: discardButtonTitle, handler: discardChangesAction))
        self.present(alert, animated: true)
    }
}

// MARK: - Data Source Proxy
private extension EditPhrasesViewController {

    func makeDataSourceProxy() -> CarouselCollectionViewDataSourceProxy<String, NSManagedObjectID> {
        let cellRegistration = phraseCellRegistration()

        return CarouselCollectionViewDataSourceProxy<String, NSManagedObjectID>(collectionView: collectionView) { [weak self] (collectionView, indexPath, _) -> UICollectionViewCell? in
            guard let self = self else { return nil }

            let phrase = self.fetchResultsController.object(at: indexPath)
            return collectionView.dequeueConfiguredReusableCell(using: cellRegistration,
                                                                for: indexPath,
                                                                item: phrase)
        }
    }

    func phraseCellRegistration() -> UICollectionView.CellRegistration<VocableListCell, Phrase> {
        UICollectionView.CellRegistration<VocableListCell, Phrase> { cell, _, phrase in
            let phraseIdentifier = phrase.objectID
            let hasImage = phrase.imageAssetID != nil
            let hasRecording = phrase.audioAssetID != nil

            let photoAction = VocableListCellAction.photo(hasImage: hasImage) { [weak self] in
                self?.handlePhotoActionTap(for: phraseIdentifier)
            }

            let recordAction = VocableListCellAction.record(hasRecording: hasRecording) { [weak self] in
                self?.handleRecordActionTap(for: phraseIdentifier)
            }

            let deleteAction = VocableListCellAction.delete(
                accessibilityIdentifier: .settings.editPhrases.deletePhraseButton
            ) { [weak self] in
                self?.presentDeletionPromptForPhrase(with: phraseIdentifier)
            }

            cell.contentConfiguration = VocableListContentConfiguration(
                title: phrase.utterance ?? "",
                actions: [photoAction, recordAction, deleteAction],
                accessory: .disclosureIndicator(),
                accessibilityIdentifier: .settings.editPhrases.editPhraseButton
            ) { [weak self] in
                self?.presentEditorForPhrase(with: phraseIdentifier)
            }
            cell.accessibilityIdentifier = phrase.identifier
        }
    }
}

// MARK: - Photo flow

extension EditPhrasesViewController: PhrasePhotoEditorDelegate {

    fileprivate func handlePhotoActionTap(for phraseID: NSManagedObjectID) {
        let context = NSPersistentContainer.shared.viewContext
        guard let store = try? ImageAssetStore() else { return }
        let viewModel = PhrasePhotoEditorViewModel(
            phraseID: phraseID,
            context: context,
            store: store,
            delegate: self
        )

        switch viewModel.mode {
        case .empty:
            viewModel.requestAddOrChange()
        case .filled:
            presentExistingPhotoMenu(for: viewModel)
        }
    }

    private func presentExistingPhotoMenu(for viewModel: PhrasePhotoEditorViewModel) {
        let title = String(
            localized: "phrase_editor.alert.photo_menu.title",
            defaultValue: "Photo"
        )
        let changeTitle = String(
            localized: "phrase_editor.alert.photo_menu.change",
            defaultValue: "Change Photo"
        )
        let removeTitle = String(
            localized: "phrase_editor.alert.photo_menu.remove",
            defaultValue: "Remove Photo"
        )
        let cancelTitle = String(
            localized: "phrase_editor.alert.photo_menu.cancel",
            defaultValue: "Cancel"
        )

        let alert = GazeableAlertViewController(alertTitle: title)
        alert.addAction(GazeableAlertAction(title: changeTitle, handler: {
            viewModel.requestAddOrChange()
        }))
        alert.addAction(GazeableAlertAction(title: removeTitle, style: .destructive, handler: {
            viewModel.requestRemove()
        }))
        alert.addAction(.cancel(withTitle: cancelTitle))
        present(alert, animated: true)
    }

    func phrasePhotoEditor(
        _ editor: PhrasePhotoEditorViewModel,
        requestsAddOrChangePhotoFor phraseID: NSManagedObjectID
    ) {
        sourceCoordinator.present(from: self) { [weak self] image in
            guard let self, let image else { return }
            self.presentCropConfirmation(for: image, phraseID: phraseID)
        }
    }

    private func presentCropConfirmation(for image: UIImage, phraseID: NSManagedObjectID) {
        let cropVC = PhotoCropViewController(
            image: image,
            onConfirm: { [weak self] cropped in
                self?.dismiss(animated: true) {
                    self?.runEnhanceAndSave(cropped, for: phraseID)
                }
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        present(cropVC, animated: true)
    }

    private func runEnhanceAndSave(_ image: UIImage, for phraseID: NSManagedObjectID) {
        enhanceCoordinator.enhance(image: image, from: self) { [weak self] enhanced in
            guard let enhanced else { return }
            self?.savePickedImage(enhanced, for: phraseID)
        }
    }

    private func savePickedImage(_ image: UIImage, for phraseID: NSManagedObjectID) {
        do {
            let store = try ImageAssetStore()
            let assetID = try store.save(image)
            let context = NSPersistentContainer.shared.viewContext
            let object = context.object(with: phraseID)
            object.setValue(assetID, forKey: "imageAssetID")
            try context.save()
        } catch {
            assertionFailure("Failed to save picked photo: \(error)")
        }
    }

    func phrasePhotoEditor(
        _ editor: PhrasePhotoEditorViewModel,
        requestsRemovalConfirmationFor phraseID: NSManagedObjectID,
        confirm: @escaping () -> Void
    ) {
        let title = String(
            localized: "phrase_editor.alert.remove_photo.title",
            defaultValue: "Remove this photo?"
        )
        let removeTitle = String(
            localized: "phrase_editor.alert.remove_photo.confirm",
            defaultValue: "Remove"
        )
        let cancelTitle = String(
            localized: "phrase_editor.alert.remove_photo.cancel",
            defaultValue: "Cancel"
        )

        let alert = GazeableAlertViewController(alertTitle: title)
        alert.addAction(.cancel(withTitle: cancelTitle))
        alert.addAction(GazeableAlertAction(title: removeTitle, style: .destructive, handler: confirm))
        present(alert, animated: true)
    }
}

// MARK: - Recording flow

extension EditPhrasesViewController: PhraseRecordingEditorDelegate {

    fileprivate func handleRecordActionTap(for phraseID: NSManagedObjectID) {
        let context = NSPersistentContainer.shared.viewContext
        guard let store = try? AudioAssetStore() else { return }
        let viewModel = PhraseRecordingEditorViewModel(
            phraseID: phraseID,
            context: context,
            store: store,
            delegate: self
        )

        switch viewModel.mode {
        case .empty:
            viewModel.requestAddOrChange()
        case .filled:
            presentExistingRecordingMenu(for: viewModel)
        }
    }

    private func presentExistingRecordingMenu(for viewModel: PhraseRecordingEditorViewModel) {
        let title = String(
            localized: "phrase_editor.alert.recording_menu.title",
            defaultValue: "Recording"
        )
        let changeTitle = String(
            localized: "phrase_editor.alert.recording_menu.change",
            defaultValue: "Re-record"
        )
        let removeTitle = String(
            localized: "phrase_editor.alert.recording_menu.remove",
            defaultValue: "Remove Recording"
        )
        let cancelTitle = String(
            localized: "phrase_editor.alert.recording_menu.cancel",
            defaultValue: "Cancel"
        )
        let toggleOnTitle = String(
            localized: "phrase_editor.alert.recording_menu.use_recording_on",
            defaultValue: "Use Recording: On"
        )
        let toggleOffTitle = String(
            localized: "phrase_editor.alert.recording_menu.use_recording_off",
            defaultValue: "Use Recording: Off"
        )

        let alert = GazeableAlertViewController(alertTitle: title)
        let toggleTitle = viewModel.prefersRecording ? toggleOnTitle : toggleOffTitle
        alert.addAction(GazeableAlertAction(title: toggleTitle, handler: {
            viewModel.togglePrefersRecording()
        }))
        alert.addAction(GazeableAlertAction(title: changeTitle, handler: {
            viewModel.requestAddOrChange()
        }))
        alert.addAction(GazeableAlertAction(title: removeTitle, style: .destructive, handler: {
            viewModel.requestRemove()
        }))
        alert.addAction(.cancel(withTitle: cancelTitle))
        present(alert, animated: true)
    }

    func phraseRecordingEditor(
        _ editor: PhraseRecordingEditorViewModel,
        requestsAddOrChangeRecordingFor phraseID: NSManagedObjectID
    ) {
        let recorder = VoiceRecorderViewController(
            onSave: { [weak self] data in
                self?.dismiss(animated: true) {
                    self?.savePickedRecording(data, for: phraseID)
                }
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        present(recorder, animated: true)
    }

    func phraseRecordingEditor(
        _ editor: PhraseRecordingEditorViewModel,
        requestsRemovalConfirmationFor phraseID: NSManagedObjectID,
        confirm: @escaping () -> Void
    ) {
        let title = String(
            localized: "phrase_editor.alert.remove_recording.title",
            defaultValue: "Remove this recording?"
        )
        let removeTitle = String(
            localized: "phrase_editor.alert.remove_recording.confirm",
            defaultValue: "Remove"
        )
        let cancelTitle = String(
            localized: "phrase_editor.alert.remove_recording.cancel",
            defaultValue: "Cancel"
        )

        let alert = GazeableAlertViewController(alertTitle: title)
        alert.addAction(.cancel(withTitle: cancelTitle))
        alert.addAction(GazeableAlertAction(title: removeTitle, style: .destructive, handler: confirm))
        present(alert, animated: true)
    }

    private func savePickedRecording(_ data: Data, for phraseID: NSManagedObjectID) {
        do {
            let store = try AudioAssetStore()
            let assetID = try store.save(data)
            let context = NSPersistentContainer.shared.viewContext
            let object = context.object(with: phraseID)
            object.setValue(assetID, forKey: "audioAssetID")
            // Default the toggle ON so newly recorded audio plays right away;
            // the caregiver can flip it off via the prefersRecording toggle.
            object.setValue(true, forKey: "prefersRecording")
            try context.save()
        } catch {
            assertionFailure("Failed to save recording: \(error)")
        }
    }
}
