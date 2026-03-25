//
//  VisualFeedbackSettingsViewController.swift
//  Vocable
//
//  Copyright © 2025 WillowTree. All rights reserved.
//

import UIKit

/// Toggle for full-screen phrase activation visual feedback (SF Symbols on iOS 17+).
final class VisualFeedbackSettingsViewController: VocableCollectionViewController {

    private enum Section: Int {
        case toggle
    }

    private enum Item: Int {
        case visualFeedbackEnabled
    }

    private typealias DataSource = UICollectionViewDiffableDataSource<Section, Item>
    private typealias Snapshot = NSDiffableDataSourceSnapshot<Section, Item>
    private typealias CellRegistration = UICollectionView.CellRegistration<VocableListCell, Item>

    private var dataSource: DataSource!
    private var cellRegistration: CellRegistration!

    override func viewDidLoad() {
        super.viewDidLoad()
        setupNavigationBar()
        setupCollectionView()
        updateDataSource()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        dataSource.reloadItem(.visualFeedbackEnabled, animated: false)
    }

    private func setupNavigationBar() {
        navigationBar.title = String(localized: "settings.visual_feedback.title")
    }

    private func setupCollectionView() {
        collectionView.delaysContentTouches = false
        collectionView.backgroundColor = .collectionViewBackgroundColor
        collectionView.isScrollEnabled = false

        let cellRegistration = CellRegistration { [weak self] cell, _, item in
            guard let self else { return }
            switch item {
            case .visualFeedbackEnabled:
                cell.contentConfiguration = VocableListContentConfiguration.toggleCell(
                    title: String(localized: "settings.visual_feedback.toggle.title"),
                    isOn: AppConfig.isVisualFeedbackEnabled,
                    accessibilityIdentifier: .settings.visualFeedback.toggle
                ) { [weak self] in
                    AppConfig.isVisualFeedbackEnabled.toggle()
                    self?.dataSource.reloadItem(.visualFeedbackEnabled, animated: true)
                }
            }
        }
        self.cellRegistration = cellRegistration

        dataSource = DataSource(collectionView: collectionView) { collectionView, indexPath, item in
            collectionView.dequeueConfiguredReusableCell(using: cellRegistration, for: indexPath, item: item)
        }

        collectionView.collectionViewLayout = UICollectionViewCompositionalLayout { [weak self] _, environment in
            self?.layoutSection(environment: environment)
        }
    }

    private func layoutSection(environment: NSCollectionLayoutEnvironment) -> NSCollectionLayoutSection {
        let itemHeight: CGFloat = sizeClass.contains(any: .compact) ? 50 : 100
        let itemSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(itemHeight)
        )
        let item = NSCollectionLayoutItem(layoutSize: itemSize)
        let groupSize = NSCollectionLayoutSize(
            widthDimension: .fractionalWidth(1.0),
            heightDimension: .absolute(itemHeight)
        )
        let group = NSCollectionLayoutGroup.horizontal(layoutSize: groupSize, subitems: [item])
        let section = NSCollectionLayoutSection(group: group)
        let horizontal = max(view.layoutMargins.left - environment.container.contentInsets.leading, 0)
        section.contentInsets = NSDirectionalEdgeInsets(
            top: 16,
            leading: horizontal,
            bottom: 16,
            trailing: horizontal
        )
        return section
    }

    private func updateDataSource(animated: Bool = false) {
        var snapshot = Snapshot()
        snapshot.appendSections([.toggle])
        snapshot.appendItems([.visualFeedbackEnabled])
        dataSource.apply(snapshot, animatingDifferences: animated)
    }

    override func viewLayoutMarginsDidChange() {
        super.viewLayoutMarginsDidChange()
        collectionView.collectionViewLayout.invalidateLayout()
    }
}
