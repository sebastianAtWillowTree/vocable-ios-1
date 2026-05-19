//
//  SquareCropper.swift
//  Vocable
//
//  Pure crop utility — independent of any view controller so it can
//  be unit-tested without UIKit lifecycle.
//

import UIKit
import CoreGraphics

enum SquareCropper {

    /// Returns the largest centered square that fits inside `image`.
    /// Pixel-accurate: uses CGImage.cropping which works in pixel space.
    static func centerSquare(_ image: UIImage) -> UIImage {
        guard let cgImage = image.cgImage else { return image }

        let pixelWidth = CGFloat(cgImage.width)
        let pixelHeight = CGFloat(cgImage.height)
        let side = min(pixelWidth, pixelHeight)
        let originX = (pixelWidth - side) / 2
        let originY = (pixelHeight - side) / 2

        let cropRect = CGRect(x: originX, y: originY, width: side, height: side).integral

        guard let cropped = cgImage.cropping(to: cropRect) else { return image }
        return UIImage(cgImage: cropped, scale: image.scale, orientation: image.imageOrientation)
    }
}
