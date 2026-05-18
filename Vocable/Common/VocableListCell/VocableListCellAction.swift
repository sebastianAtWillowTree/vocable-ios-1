//
//  VocableListCellAction.swift
//  Vocable
//
//  Created by Chris Stroud on 3/23/22.
//  Copyright © 2022 WillowTree. All rights reserved.
//

import UIKit

struct VocableListCellAction: Equatable {

    typealias Action = () -> Void

    let image: UIImage
    let action: Action?
    let isEnabled: Bool
    let accessibilityIdentifier: AccessibilityID?
    let accessibilityLabel: String?

    private init(
        image: UIImage,
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        accessibilityLabel: String? = nil,
        action: Action? = nil
    ) {
        self.image = image
        self.isEnabled = isEnabled
        self.action = action
        self.accessibilityIdentifier = accessibilityIdentifier
        self.accessibilityLabel = accessibilityLabel
    }

    private init(
        systemImage imageName: String,
        symbolConfiguration: UIImage.SymbolConfiguration? = nil,
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        accessibilityLabel: String? = nil,
        action: Action? = nil
    ) {
        let image = UIImage(
            systemName: imageName,
            withConfiguration: symbolConfiguration
        )!
        self.init(
            image: image,
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel ?? imageName,
            action: action
        )
    }

    private static var defaultSymbolConfiguration: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: 48, weight: .bold)
    }

    private static var trailingDefaultSymbolConfiguration: UIImage.SymbolConfiguration {
        UIImage.SymbolConfiguration(pointSize: 28, weight: .bold)
    }

    static func delete(
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        accessibilityLabel: String = "delete",
        action: Action?
    ) -> VocableListCellAction {
        VocableListCellAction(
            systemImage: "trash",
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }

    static func reorderUp(
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        accessibilityLabel: String = "reorder up",
        action: Action?
    ) -> VocableListCellAction {
        VocableListCellAction(
            systemImage: "chevron.up",
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }
    
    static func reorderDown(
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        accessibilityLabel: String = "reorder down",
        action: Action?
    ) -> VocableListCellAction {
        VocableListCellAction(
            systemImage: "chevron.down",
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }

    static func startAudio(
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        accessibilityLabel: String = "play sample",
        action: Action?
    ) -> VocableListCellAction {
        VocableListCellAction(
            systemImage: "play.circle",
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }

    static func stopAudio(
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        accessibilityLabel: String = "audio is playing",
        action: Action?
    ) -> VocableListCellAction {
        VocableListCellAction(
            systemImage: "stop.circle",
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: accessibilityLabel,
            action: action
        )
    }

    static func photo(
        hasImage: Bool,
        isEnabled: Bool = true,
        accessibilityIdentifier: AccessibilityID? = nil,
        action: Action?
    ) -> VocableListCellAction {
        VocableListCellAction(
            systemImage: hasImage ? "photo.circle" : "camera.circle",
            isEnabled: isEnabled,
            accessibilityIdentifier: accessibilityIdentifier,
            accessibilityLabel: hasImage ? "change photo" : "add photo",
            action: action
        )
    }

    static func == (lhs: VocableListCellAction, rhs: VocableListCellAction) -> Bool {
        lhs.isEnabled == rhs.isEnabled &&
        lhs.accessibilityIdentifier == rhs.accessibilityIdentifier &&
        lhs.image.isEqual(rhs.image)
    }
}
