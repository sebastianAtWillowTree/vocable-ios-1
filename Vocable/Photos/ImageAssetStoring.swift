//
//  ImageAssetStoring.swift
//  Vocable
//
//  Protocol seam for image asset persistence so the rest of the
//  photo feature can be tested with in-memory or fake stores.
//

import UIKit

protocol ImageAssetStoring {
    func save(_ image: UIImage) throws -> String
    func load(id: String) -> UIImage?
    func delete(id: String) throws
    func allAssetIDs() -> [String]
}
