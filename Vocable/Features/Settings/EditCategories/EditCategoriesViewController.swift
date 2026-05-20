//
//  EditCategoriesViewController.swift
//  Vocable AAC
//
//  Created by Jesse Morgan on 3/31/20.
//  Copyright © 2020 WillowTree. All rights reserved.
//

import Combine
import CoreData
import UIKit

final class EditCategoriesViewController: PagingCarouselViewController, NSFetchedResultsControllerDelegate {

    private var carouselCollectionViewController: CarouselGridCollectionViewController?
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

    private var cellRegistration: UICollectionView.CellRegistration<VocableListCell, Category>!

    private lazy var diffableDataSource = CarouselCollectionViewDataSourceProxy<String, NSManagedObjectID>(collectionView: collectionView) { [weak self] (collectionView, indexPath, category) -> UICollectionViewCell? in
        guard let self = self else { return nil }
        let category = self.fetchResultsController.managedObjectContext.object(with: category) as! Category
        return collectionView.dequeueConfiguredReusableCell(using: self.cellRegistration,
                                                            for: indexPath,
                                                            item: category)
    }

    private lazy var fetchRequest: NSFetchRequest<Category> = {
        let request: NSFetchRequest<Category> = Category.fetchRequest()
        request.predicate = Category.visibleCategoriesPredicate()
        request.sortDescriptors = [NSSortDescriptor(keyPath: \Category.isHidden, ascending: true),
        NSSortDescriptor(keyPath: \Category.ordinal, ascending: true),
        NSSortDescriptor(keyPath: \Category.creationDate, ascending: true)]
        return request
    }()

    private lazy var fetchResultsController = NSFetchedResultsController<Category>(fetchRequest: self.fetchRequest,
                                                                                   managedObjectContext: NSPersistentContainer.shared.viewContext,
                                                                                   sectionNameKeyPath: nil,
                                                                                   cacheName: nil)

    override func viewDidLoad() {
        super.viewDidLoad()

        setupNavigationBar()
        setupCollectionView()

        updateLayoutForCurrentTraitCollection()

        fetchResultsController.delegate = self
        try? fetchResultsController.performFetch()
    }

    private func setupNavigationBar() {
        navigationBar.title = String(localized: "categories_list_editor.header.title")

        navigationBar.leftButton = {
            let button = GazeableButton(frame: .zero)
            button.setImage(UIImage(systemName: "arrow.left"), for: .normal)
            button.addTarget(self, action: #selector(backToEditCategories), for: .primaryActionTriggered)
            button.accessibilityID = .shared.backButton
            return button
        }()

        navigationBar.rightButton = {
            let button = GazeableButton(frame: .zero)
            button.setImage(UIImage(systemName: "plus"), for: .normal)
            button.accessibilityID = .settings.editCategories.addCategoryButton
            button.addTarget(self, action: #selector(addButtonPressed), for: .primaryActionTriggered)
            return button
        }()
    }

    private func setupCollectionView() {
        collectionView.backgroundColor = .collectionViewBackgroundColor
        cellRegistration = UICollectionView.CellRegistration<VocableListCell, Category>(handler: { [weak self] cell, indexPath, category in
            self?.updateContentConfiguration(for: cell, at: indexPath, category: category)
        })
    }

    private func updateContentConfiguration(for cell: VocableListCell, at indexPath: IndexPath, category: Category) {
        let categoryID = category.objectID

        let upAction = VocableListCellAction.reorderUp(
            isEnabled: category.canMoveToLowerOrdinal,
            accessibilityIdentifier: .settings.editCategories.moveUpButton
        ) { [weak self] in
            self?.handleMoveUpForCategory(withObjectID: categoryID)
        }

        let downAction = VocableListCellAction.reorderDown(
            isEnabled: category.canMoveToHigherOrdinal,
            accessibilityIdentifier: .settings.editCategories.moveDownButton
        ) { [weak self] in
            self?.handleMoveDownForCategory(withObjectID: categoryID)
        }

        let photoAction = VocableListCellAction.photo(
            hasImage: category.imageAssetID != nil
        ) { [weak self] in
            self?.handlePhotoActionTap(for: categoryID)
        }

        var config = VocableListContentConfiguration(
            title: category.name ?? "",
            actions: [upAction, downAction, photoAction],
            accessory: .disclosureIndicator(),
            accessibilityIdentifier: .settings.editCategories.categoryButton
        ) { [weak self] in
            self?.showEditForCategory(withObjectID: categoryID)
        }

        config.traitCollectionChangeHandler = { (traitCollection, newConfig) in
            if traitCollection.horizontalSizeClass == .compact && traitCollection.verticalSizeClass == .regular {
                newConfig.actionsConfiguration.position = .bottom
            } else {
                newConfig.actionsConfiguration.position = .leading
            }
            if [traitCollection.horizontalSizeClass, traitCollection.verticalSizeClass].contains(.compact) {
                newConfig.actionsConfiguration.size.widthDimension = .fractionalHeight(1.6)
            } else {
                newConfig.actionsConfiguration.size.widthDimension = .fractionalHeight(1.0)
            }
        }

        cell.contentConfiguration = config
        cell.accessibilityIdentifier = category.identifier
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateLayoutForCurrentTraitCollection()
        DispatchQueue.main.async {
            self.collectionView.reloadData()
        }
    }
    
    private func updateLayoutForCurrentTraitCollection() {
        collectionView.layout.numberOfColumns = .fixedCount(1)

        switch (traitCollection.horizontalSizeClass, traitCollection.verticalSizeClass) {
        case (.regular, .regular):
            collectionView.layout.interItemSpacing = .uniform(8)
            collectionView.layout.numberOfRows = .flexible(minHeight: .absolute(75))
        case (.compact, .regular):
            collectionView.layout.interItemSpacing = .uniform(32)
            collectionView.layout.numberOfRows = .flexible(minHeight: .absolute(108), maxHeight: .absolute(108))
        case (.compact, .compact), (.regular, .compact):
            collectionView.layout.interItemSpacing = .uniform(8)
            collectionView.layout.numberOfRows = .flexible(minHeight: .absolute(50))
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
        let snapshot = snapshot as NSDiffableDataSourceSnapshot<String, NSManagedObjectID>
        let shouldAnimate = view.window != nil
        self.diffableDataSource.apply(snapshot, animatingDifferences: shouldAnimate) { [weak self] in
            guard
                let self,
                let window = self.view.window as? HeadGazeWindow,
                let target = window.activeGazeTarget
            else {
                return
            }
            if let _ = self.collectionView.indexPath(containing: target) {
                window.cancelActiveGazeTarget()
            }
        }
    }

    private func indexPathForCategory(withObjectID objectID: NSManagedObjectID) -> IndexPath? {
        guard let category = fetchResultsController.managedObjectContext.object(with: objectID) as? Category else {
            return nil
        }

        guard let standardIndexPath = fetchResultsController.indexPath(forObject: category) else {
            assertionFailure("Failed to obtain index path")
            return nil
        }

        return diffableDataSource.indexPath(fromVirtual: standardIndexPath)
    }

    private func handleMoveUpForCategory(withObjectID objectID: NSManagedObjectID) {

        guard let fromIndexPath = indexPathForCategory(withObjectID: objectID) else {
            return
        }
        guard let toIndexPath = collectionView.indexPath(before: fromIndexPath) else {
            return
        }

        let fromCategory = fetchResultsController.object(at: fromIndexPath)
        let toCategory = fetchResultsController.object(at: toIndexPath)

        swapOrdinal(fromCategory: fromCategory, toCategory: toCategory)
    }

    private func handleMoveDownForCategory(withObjectID objectID: NSManagedObjectID) {

        guard let fromIndexPath = indexPathForCategory(withObjectID: objectID) else {
            return
        }
        guard let toIndexPath = collectionView.indexPath(after: fromIndexPath) else {
            return
        }
        let fromCategory = fetchResultsController.object(at: fromIndexPath)
        let toCategory = fetchResultsController.object(at: toIndexPath)

        swapOrdinal(fromCategory: fromCategory, toCategory: toCategory)
    }

    private func showEditForCategory(withObjectID objectID: NSManagedObjectID) {

        guard let category = fetchResultsController.managedObjectContext.object(with: objectID) as? Category else {
            return
        }

        let destination: UIViewController
        if category.identifier == Category.Identifier.listeningMode.rawValue {
            destination = ListeningModeViewController()
        } else {
            destination = EditCategoryDetailViewController(category)
        }
        show(destination, sender: nil)
    }

    private func swapOrdinal(fromCategory: Category, toCategory: Category) {

        let fromCategoryID = fromCategory.objectID
        let toCategoryID = toCategory.objectID

        let context = NSPersistentContainer.shared.newBackgroundContext()
        context.perform {

            guard
                let fromCategory = context.object(with: fromCategoryID) as? Category,
                let toCategory = context.object(with: toCategoryID) as? Category
            else {
                return
            }

            let fromOrdinal = fromCategory.ordinal
            let toOrdinal = toCategory.ordinal

            fromCategory.ordinal = toOrdinal
            toCategory.ordinal = fromOrdinal
            try? Category.updateAllOrdinalValues(in: context)

            do {
                try context.save()
            } catch {
                assertionFailure("Failed to save context: \(error)")
            }
        }
    }

    @objc private func backToEditCategories(_ sender: Any) {
        self.navigationController?.popViewController(animated: true)
    }
    
    @objc private func addButtonPressed(_ sender: Any) {
        let viewController = TextEditorViewController()
        let context = NSPersistentContainer.shared.newBackgroundContext()
        viewController.delegate = CategoryNameEditorConfigurationProvider(context: context)

        viewController.modalPresentationStyle = .fullScreen
        present(viewController, animated: true)
    }

}

// MARK: - Photo flow

extension EditCategoriesViewController: CategoryPhotoEditorDelegate {

    fileprivate func handlePhotoActionTap(for categoryID: NSManagedObjectID) {
        let context = NSPersistentContainer.shared.viewContext
        guard let store = try? ImageAssetStore() else { return }
        let viewModel = CategoryPhotoEditorViewModel(
            categoryID: categoryID,
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

    private func presentExistingPhotoMenu(for viewModel: CategoryPhotoEditorViewModel) {
        let title = String(
            localized: "category_editor.alert.photo_menu.title",
            defaultValue: "Photo"
        )
        let changeTitle = String(
            localized: "category_editor.alert.photo_menu.change",
            defaultValue: "Change Photo"
        )
        let removeTitle = String(
            localized: "category_editor.alert.photo_menu.remove",
            defaultValue: "Remove Photo"
        )
        let cancelTitle = String(
            localized: "category_editor.alert.photo_menu.cancel",
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

    func categoryPhotoEditor(
        _ editor: CategoryPhotoEditorViewModel,
        requestsAddOrChangePhotoFor categoryID: NSManagedObjectID
    ) {
        sourceCoordinator.present(from: self) { [weak self] image in
            guard let self, let image else { return }
            self.presentCropConfirmation(for: image, categoryID: categoryID)
        }
    }

    func categoryPhotoEditor(
        _ editor: CategoryPhotoEditorViewModel,
        requestsRemovalConfirmationFor categoryID: NSManagedObjectID,
        confirm: @escaping () -> Void
    ) {
        let title = String(
            localized: "category_editor.alert.remove_photo.title",
            defaultValue: "Remove this photo?"
        )
        let removeTitle = String(
            localized: "category_editor.alert.remove_photo.confirm",
            defaultValue: "Remove"
        )
        let cancelTitle = String(
            localized: "category_editor.alert.remove_photo.cancel",
            defaultValue: "Cancel"
        )

        let alert = GazeableAlertViewController(alertTitle: title)
        alert.addAction(.cancel(withTitle: cancelTitle))
        alert.addAction(GazeableAlertAction(title: removeTitle, style: .destructive, handler: confirm))
        present(alert, animated: true)
    }

    private func presentCropConfirmation(for image: UIImage, categoryID: NSManagedObjectID) {
        let cropVC = PhotoCropViewController(
            image: image,
            onConfirm: { [weak self] cropped in
                self?.dismiss(animated: true) {
                    self?.runEnhanceAndSave(cropped, for: categoryID)
                }
            },
            onCancel: { [weak self] in
                self?.dismiss(animated: true)
            }
        )
        present(cropVC, animated: true)
    }

    private func runEnhanceAndSave(_ image: UIImage, for categoryID: NSManagedObjectID) {
        enhanceCoordinator.enhance(image: image, from: self) { [weak self] enhanced in
            guard let enhanced else { return }
            self?.savePickedImage(enhanced, for: categoryID)
        }
    }

    private func savePickedImage(_ image: UIImage, for categoryID: NSManagedObjectID) {
        do {
            let store = try ImageAssetStore()
            let assetID = try store.save(image)
            let context = NSPersistentContainer.shared.viewContext
            let object = context.object(with: categoryID)
            object.setValue(assetID, forKey: "imageAssetID")
            try context.save()
        } catch {
            assertionFailure("Failed to save category photo: \(error)")
        }
    }
}
